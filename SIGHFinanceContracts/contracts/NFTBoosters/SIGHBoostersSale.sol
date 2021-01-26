// SPDX-License-Identifier: agpl-3.0
pragma experimental ABIEncoderV2;
pragma solidity 0.7.0;

import "../dependencies/openzeppelin/access/Ownable.sol";
import "../dependencies/openzeppelin/math/SafeMath.sol";
import "../dependencies/openzeppelin/token/ERC20/ERC20.sol";
import "../dependencies/BoostersDependencies/BoostersStringUtils.sol";

import "../../interfaces/NFTBoosters/ISIGHBoosters.sol";
import "../../interfaces/NFTBoosters/ISIGHBoostersSale.sol";

contract SIGHBoostersSale is Ownable,ISIGHBoostersSale {

    using BoostersStringUtils for string;
    using SafeMath for uint256;

    ISIGHBoosters private _SIGH_NFT_BoostersContract;    // SIGH Finance NFT Boosters Contract
    uint public initiateTimestamp;

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

    constructor(address _SIGHNFTBoostersContract) {
        require(_SIGHNFTBoostersContract != address(0),'SIGH Finance : Invalid _SIGHNFTBoostersContract address');
        _SIGH_NFT_BoostersContract = ISIGHBoosters(_SIGHNFTBoostersContract);
    }

    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    function addBoostersForSale(string memory _BoosterType, uint256[] memory boosterids) external override onlyOwner {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_BoosterType),"Invalid Type");

        if (!boosterTypes[_BoosterType]) {
            boosterTypes[_BoosterType] = true;
        }

        for (uint i; i < boosterids.length; i++ ) {
            require( !boosterIdsForSale[boosterids[i]], "Already Added");

            ( , string memory _type, , ) = _SIGH_NFT_BoostersContract.getBoosterInfo(boosterids[i]);
            require(_type.equal(_BoosterType),"Different type");

            listOfBoosters[_type].boosterIdsList.push( boosterids[i] ); // ADDED the boosterID to the list of Boosters available for sale
            listOfBoosters[_type].totalAvailable = listOfBoosters[_type].totalAvailable.add(1); // Incremented total available by 1
            boosterIdsForSale[boosterids[i]] = true;

            emit BoosterAddedForSale(_BoosterType , boosterids[i]);
        }
    }

    // Updates the Sale price for '_BoosterType' type of Boosters. Only owner can call this function
    function updateSalePrice(string memory _BoosterType, uint256 _price ) external override onlyOwner {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_BoosterType),"Invalid Type");
        require( boosterTypes[_BoosterType] ,"Not yet initialized");
        listOfBoosters[_BoosterType].salePrice = _price;
        emit SalePriceUpdated(_BoosterType,_price);
    }

    // Update the token accepted as payment
    function updateAcceptedToken(address token) external override onlyOwner {
        require( token != address(0) ,"Invalid address");
        tokenAcceptedAsPayment = ERC20(token);
        emit PaymentTokenUpdated(token);
    }

    // Transfers part of the collected Funds to the 'to' address . Only owner can call this function
    function transferBalance(address to, uint amount) external override onlyOwner {
        require( to != address(0) ,"Invalid address");
        require( amount <= getCurrentBalance() ,"Invalid amount");
        tokenAcceptedAsPayment.transfer(to,amount);
        emit FundsTransferred(amount);
    }

    // Updates time when the Booster sale will go live
    function updateSaleTime(uint timestamp) external override onlyOwner {
        require( block.timestamp < timestamp,'Invalid stamp');
        initiateTimestamp = timestamp;
        emit SaleTimeUpdated(initiateTimestamp);
    }

    // Transfers part of the collected DAI to the 'to' address . Only owner can call this function
    function transferTokens(address token, address to, uint amount) external override onlyOwner {
        require( to != address(0) ,"Invalid address");
        ERC20 token_ = ERC20(token);
        uint balance = token_.balanceOf(address(this));
        require( amount <= balance ,"Invalid amount");
        token_.transfer(to,amount);
    }

    // ##########################################
    // ######## FUNCTION TO BY A BOOSTER ########
    // ##########################################

    function buyBoosters(address receiver, string memory _BoosterType, uint boostersToBuy) override external {
        require( block.timestamp > initiateTimestamp,'Sale not begin');
        require(boostersToBuy >= 1,"Invalid number of boosters");
        require(boosterTypes[_BoosterType],"Invalid Booster Type");
        require(listOfBoosters[_BoosterType].totalAvailable >=  boostersToBuy,"Boosters not available");

        uint amountToBePaid = boostersToBuy.mul(listOfBoosters[_BoosterType].salePrice);

        require(transferFunds(msg.sender,amountToBePaid),'Funds transfer Failed');
        require(transferBoosters(receiver, _BoosterType, boostersToBuy),'Boosters transfer Failed');
    }


    // #########################################
    // ######## EXTERNAL VIEW FUNCTIONS ########
    // #########################################

    function getBoosterSaleDetails(string memory _Boostertype) external view override returns (uint256 available,uint256 price, uint256 sold) {
        require( _SIGH_NFT_BoostersContract.isCategorySupported(_Boostertype),"SIGH Finance : Not a valid Booster Type");
        available = listOfBoosters[_Boostertype].totalAvailable;
        price = listOfBoosters[_Boostertype].salePrice;
        sold = listOfBoosters[_Boostertype].totalBoostersSold;
    }

    function getTokenAccepted() public view override returns(string memory symbol, address tokenAddress) {
        symbol = tokenAcceptedAsPayment.symbol();
        tokenAddress = address(tokenAcceptedAsPayment);
    }

    function getCurrentFundsBalance() public view override returns (uint256) {
        require(tokenAcceptedAsPayment!=address(0));
        return tokenAcceptedAsPayment.balanceOf(address(this));
    }

    function getTokenBalance(address token) public view override returns (uint256) {
        require(tokenAcceptedAsPayment!=address(0));
        ERC20 token_ = ERC20(token);
        uint balance = token_.balanceOf(address(this));
        return balance;
    }
    // ####################################
    // ######## INTERNAL FUNCTIONS ########
    // ####################################

    // Transfers 'totalBoosters' number of BOOSTERS of type '_BoosterType' to the 'to' address
    function transferBoosters(address to, string memory _BoosterType, uint totalBoosters) internal returns (bool) {
        uint counter;
        uint listLength = listOfBoosters[_BoosterType].boosterIdsList.length;

        for (uint i; i < listLength; i++ ) {
            uint256 _boosterId = listOfBoosters[_BoosterType].boosterIdsList[i];  // current BoosterID

            if (boosterIdsForSale[_boosterId] && listOfBoosters[_BoosterType].boosterIdsList[i] > 0) {

                // Transfer the Booster and Verify the same
                _SIGH_NFT_BoostersContract.safeTransferFrom(address(this),to,_boosterId);
                require(to == _SIGH_NFT_BoostersContract.ownerOfBooster(_boosterId),"Booster Transfer failed");

                // Remove the Booster ID
                listOfBoosters[_BoosterType].boosterIdsList[i] = listOfBoosters[_BoosterType].boosterIdsList[listLength.sub(1)];
                listOfBoosters[_BoosterType].boosterIdsList.pop();

                // Update the number of boosters available & sold
                listOfBoosters[_BoosterType].totalAvailable = listOfBoosters[_BoosterType].totalAvailable.sub(1);
                listOfBoosters[_BoosterType].totalBoostersSold = listOfBoosters[_BoosterType].totalBoostersSold.add(1);

                // Mark the BoosterID as sold and update the counter
                boosterIdsForSale[_boosterId] = false;
                counter = counter.add(1);

                emit BoosterSold(to, _BoosterType, _boosterId, listOfBoosters[_BoosterType].salePrice );

                if (counter == totalBoosters) {
                    return true;
                }
            }
        }
        return false;
    }

    // Transfers 'amount' of DAI to the contract
    function transferFunds(address from, uint amount) internal returns (bool) {
        uint prevBalance = tokenAcceptedAsPayment.balanceOf(address(this));
        tokenAcceptedAsPayment.transferFrom(from,address(this),amount);
        uint newBalance = tokenAcceptedAsPayment.balanceOf(address(this));
        require(newBalance == prevBalance.add(amount),'Funds Transfer failed');
        return true;
    }

}