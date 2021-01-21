// SPDX-License-Identifier: agpl-3.0
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../dependencies/openzeppelin/access/Ownable.sol";
import "../dependencies/openzeppelin/math/SafeMath.sol";
import "../dependencies/openzeppelin/token/ERC20/ERC20.sol";
import "../dependencies/BoostersDependencies/BoostersStringUtils.sol";

import "../../interfaces/NFTBoosters/ISIGHBoosters.sol";

contract SIGHBoostersSale is Ownable {

    using BoostersStringUtils for string;
    using SafeMath for uint256;

    ISIGHBoosters private _SIGH_NFT_BoostersContract;    // SIGH Finance NFT Boosters Contract
    address private _BoosterVault;

    ERC20 private tokenAcceptedAsPayment;         // Address of token accepted as payment

    struct boosterList {
        uint256 totalAvailable;             // No. of Boosters of a particular type currently available for sale
        uint256[] boosterIdsList;          // List of BoosterIds for the boosters of a particular type currently available for sale
        uint256 salePrice;                  // Sale price for a particular type of Booster
        uint256 totalBoostersSold;           // Boosters sold
    }

    mapping (string => boosterList) private listOfBoosters;   // (Booster Type => boosterList struct)
    mapping (uint256 => bool) private boosterIdsForSale;      // Booster Ids that have been included for sale
    mapping (string => bool) private boosterTypes;            // Booster Type => Yes/No

    event BoosterSold(address to, string _BoosterType, uint _boosterId, uint salePrice );

    constructor(address _SIGHNFTBoostersContract) {
        require(_SIGHNFTBoostersContract != address(0),'SIGH Finance : Invalid _SIGHNFTBoostersContract address');
        _SIGH_NFT_BoostersContract = ISIGHBoosters(_SIGHNFTBoostersContract);
    }

    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    function addBoostersForSale(string memory _BoosterType, uint256[] memory boosterids, uint256 _price ) external onlyOwner {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_BoosterType),"SIGH Finance : Not a valid Booster Type");

        if (!boosterTypes[_BoosterType]) {
            boosterTypes[_BoosterType] = true;
        }

        for (uint i; i < boosterids.length; i++ ) {
            require( !boosterIdsForSale[boosterids[i]], "Booster already added for sale");

            ( , string memory _type) = _SIGH_NFT_BoostersContract.getBoosterInfo(boosterids[i]);
            require(_type.equal(_BoosterType),"Booster of different type");

            listOfBoosters[_type].boosterIdsList.push( boosterids[i] ); // ADDED the boosterID to the list of Boosters available for sale
            listOfBoosters[_type].totalAvailable = listOfBoosters[_type].totalAvailable.add(1); // Incremented total available by 1
            boosterIdsForSale[boosterids[i]] = true;
        }
    }

    // Updates the Sale price for '_BoosterType' type of Boosters. Only owner can call this function
    function updateSalePrice(string memory _BoosterType, uint256 _price ) external onlyOwner {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_BoosterType),"SIGH Finance : Not a valid Booster Type");
        require( boosterTypes[_BoosterType] ,"SIGH Finance : Booster Type not initialized yet");

        listOfBoosters[_BoosterType].salePrice = _price;
    }

    // Transfers part of the collected DAI to the 'to' address . Only owner can call this function
    function updateAcceptedToken(address token) external onlyOwner {
        require( token != address(0) ,"Invalid destination address");
        tokenAcceptedAsPayment = ERC20(token);
    }

    // Transfers part of the collected DAI to the 'to' address . Only owner can call this function
    function transferBalance(address to, uint amount) external onlyOwner {
        require( to != address(0) ,"Invalid destination address");
        require( amount <= getCurrentBalance() ,"Invalid amount");
        tokenAcceptedAsPayment.transfer(to,amount);
    }

    // ##########################################
    // ######## FUNCTION TO BY A BOOSTER ########
    // ##########################################

    function buyBoosters(string memory _BoosterType, uint boostersToBuy) external {
        require(boostersToBuy >= 1,"Invalid number of boosters provided");
        require(boosterTypes[_BoosterType],"Invalid Booster Type");
        require(listOfBoosters[_BoosterType].totalAvailable >=  boostersToBuy,"Desired Number of boosters not available");

        uint amountToBePaid = boostersToBuy.mul(listOfBoosters[_BoosterType].salePrice);

        transferFunds(msg.sender,amountToBePaid);
        transferBoosters(msg.sender, _BoosterType, boostersToBuy);
    }


    // #########################################
    // ######## EXTERNAL VIEW FUNCTIONS ########
    // #########################################

    function getBoosterSaleDetails(string memory _Boostertype) external view returns (uint256 available,uint256 price, uint256 sold) {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_Boostertype),"SIGH Finance : Not a valid Booster Type");
        available = listOfBoosters[_Boostertype].totalAvailable;
        price = listOfBoosters[_Boostertype].salePrice;
        sold = listOfBoosters[_Boostertype].totalBoostersSold;
    }

    function getTokenAccepted() public view returns(string memory symbol, address tokenAddress) {
        symbol = tokenAcceptedAsPayment.symbol();
        tokenAddress = address(tokenAcceptedAsPayment);
    }

    function getCurrentBalance() public view returns (uint256) {
        return tokenAcceptedAsPayment.balanceOf(address(this));
    }

    // ####################################
    // ######## INTERNAL FUNCTIONS ########
    // ####################################

    // Transfers 'totalBoosters' number of BOOSTERS of type '_BoosterType' to the 'to' address
    function transferBoosters(address to, string memory _BoosterType, uint totalBoosters) internal {
        uint counter;
        uint listLength = listOfBoosters[_BoosterType].boosterIdsList.length;

        for (uint i; i < listLength; i++ ) {
            uint256 _boosterId = listOfBoosters[_BoosterType].boosterIdsList[i];  // current BoosterID

            if (boosterIdsForSale[_boosterId]) {
                // Transfer the Booster and Verify the same
                _SIGH_NFT_BoostersContract.safeTransferFrom(_BoosterVault,to,_boosterId);
                require(to == _SIGH_NFT_BoostersContract.ownerOfBooster(_boosterId),"Booster Transfer failed");

                // Remove the Booster ID from the list of Boosters available
                listOfBoosters[_BoosterType].boosterIdsList[i] = listOfBoosters[_BoosterType].boosterIdsList[listLength - 1];
                listOfBoosters[_BoosterType].boosterIdsList[i].length--;

                // Update the number of boosters available & sold
                listOfBoosters[_BoosterType].totalAvailable = listOfBoosters[_BoosterType].totalAvailable.sub(1);
                listOfBoosters[_BoosterType].totalBoostersSold = listOfBoosters[_BoosterType].totalBoostersSold.add(1);

                // Mark the BoosterID as sold and update the counter
                boosterIdsForSale[_boosterId] = false;
                counter = counter.add(1);

                emit BoosterSold(to, _BoosterType, _boosterId, listOfBoosters[_BoosterType].salePrice );

                if (counter == totalBoosters) {
                    break;
                }
            }
        }
    }

    // Transfers 'amount' of DAI to the contract
    function transferFunds(address from, uint amount) internal {
        uint prevBalance = tokenAcceptedAsPayment.balanceOf(address(this));
        tokenAcceptedAsPayment.transferFrom(from,address(this),amount);
        uint newBalance = tokenAcceptedAsPayment.balanceOf(address(this));
        require(newBalance == prevBalance.add(amount),'DAI transfer failure');
    }

}