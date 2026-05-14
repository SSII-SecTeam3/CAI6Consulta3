// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Auction is ReentrancyGuard {
    string public medicalEquipment;
    uint256 public immutable auctionStartDate;
    uint256 public immutable auctionEndDate;
    uint8 public immutable maximumBid;
    address public immutable owner;

    mapping(address => uint8) private bidPerSupplier;
    mapping(address => uint256) private deposits;
    address[] private suppliers;
    uint8[] private bids;

    address private supplierSelected;
    uint8 public quantityToPay;
    bool public auctionEnded;

    constructor(string memory _medicalEquipment, uint8 _maximumBid, uint256 _auctionDurationDays) {
        require(_maximumBid > 0, unicode"El valor máximo de puja debe ser mayor que 0");
        require(_auctionDurationDays > 0, unicode"La duración de la subasta debe ser de al menos 1 día");

        medicalEquipment = _medicalEquipment;
        maximumBid = _maximumBid;
        auctionStartDate = block.timestamp;
        auctionEndDate = block.timestamp + (_auctionDurationDays * 1 days);
        auctionEnded = false;
        owner = msg.sender;
    }

    function bid(uint8 _quantity) public payable {
        require(!auctionEnded, "La subasta ha terminado");
        require(_quantity > 0, "La puja debe ser un valor positivo mayor que 0");
        require(_quantity <= maximumBid, unicode"La puja debe ser un valor igual o por debajo del valor máximo definido por el servicio de salud");
        require(bidPerSupplier[msg.sender] == 0, "Ya has realizado una puja");

        uint256 deposit = (uint256(_quantity) * 10) / 100;
        require(msg.value >= deposit, "Debes enviar al menos el 10% de tu puja como deposito");

        bidPerSupplier[msg.sender] = _quantity;
        deposits[msg.sender] += msg.value;
        suppliers.push(msg.sender);
        bids.push(_quantity);

        if(suppliers.length == 30) {
            endAuction();
        }
    }

    function checkAuctionEndDatePassed() external {
        uint256 currentDate = block.timestamp;
        if(currentDate > auctionEndDate) {
            endAuction();
        }
    }

    function endAuction() internal {
        require(!auctionEnded, "La subasta ya ha terminado");
        auctionEnded = true;
        uint8 minValue = maximumBid;
        uint8 secondMinValue = maximumBid;
        if(suppliers.length == 0) {
        } else if (suppliers.length == 1) {
            supplierSelected = suppliers[0];
            quantityToPay = bidPerSupplier[supplierSelected];
        } else {
            uint256 len = suppliers.length; // Optimizamos gas (cache-array-length)
            for (uint256 i = 0; i < len; i++) {
                uint8 bidPayed = bidPerSupplier[suppliers[i]];
                if (bidPayed < minValue) {
                    secondMinValue = minValue;
                    minValue = bidPayed;
                    supplierSelected = suppliers[i];
                    quantityToPay = secondMinValue;
                } else if (bidPayed < secondMinValue && bidPayed != minValue) {
                    secondMinValue = bidPayed;
                    quantityToPay = secondMinValue;
                }
            }
            refundDepositParticipants();
        }
    }

    // slither-disable-next-line reentrancy-eth
    function refundDepositParticipants() internal nonReentrant { 
        require(auctionEnded, "La subasta no ha terminado");
        
        uint256 len = suppliers.length; // Optimizamos gas (cache-array-length)
        for (uint256 i = 0; i < len; i++) {
            address payable supplier = payable(suppliers[i]);
            
            if (supplier != supplierSelected) {
                uint256 amount = deposits[supplier];
                
                if (amount > 0) {
                    deposits[supplier] = 0;
                    
                    (bool sent, ) = supplier.call{value: amount}("");
                    require(sent, "Fallo al enviar ETH");
                }
            }
        }
    }

    function payDepositSupplierSelected() public {
        require(auctionEnded, "La subasta no ha terminado");
        require(msg.sender == owner, unicode"Solo el dueño puede pagar al proveedor seleccionado");
        require(supplierSelected != address(0), "No hay proveedor seleccionado");
        uint256 amount = deposits[supplierSelected];
        require(amount > 0, "No hay deposito para pagar");
        deposits[supplierSelected] = 0;
        amount += quantityToPay;
        (bool sent, ) = payable(supplierSelected).call{value: amount}("");
        require(sent, "Fallo al enviar ETH");
    }

    function penalizeSupplier() public {
        require(auctionEnded, "La subasta no ha terminado");
        require(msg.sender == owner, unicode"Solo el dueño puede penalizar al proveedor seleccionado");
        require(supplierSelected != address(0), "No hay proveedor seleccionado");
        uint256 amount = deposits[supplierSelected];
        require(amount > 0, "No hay deposito para penalizar");

        deposits[supplierSelected] = 0;
    }

    function getSupplierSelected() external view returns (address) {
        require(auctionEnded, "La subasta no ha terminado");
        return supplierSelected;
    }

    function getBidPerSupplier() external view returns (address[] memory, uint8[] memory) {
        require(auctionEnded, "La subasta no ha terminado");
        return (suppliers, bids);
    }
}