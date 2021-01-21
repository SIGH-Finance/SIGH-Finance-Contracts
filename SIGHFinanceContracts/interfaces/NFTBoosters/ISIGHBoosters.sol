// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface ISIGHBoosters {

    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    function createNewSIGHBooster(address _owner, string memory _type,  string memory boosterURI, bytes memory _data ) external returns (uint256) ;
    function addNewBoosterType(string memory _type, uint256 _platformFeeDiscount_, uint256 _sighPayDiscount_) external returns (bool) ;
    function updateBoosterURI(uint256 boosterId, string memory boosterURI )  external returns (bool) ;

    // ###########################################
    // ######## STANDARD ERC721 FUNCTIONS ########
    // ###########################################

    function name() external view  returns (string memory) ;

    function symbol() external view  returns (string memory) ;

    // Returns total number of Boosters owned by the _owner
    function balanceOf(address _owner) external view returns (uint256 balance) ;

    //  See {IERC721Enumerable-tokenOfOwnerByIndex}.
    function tokenOfOwnerByIndex(address owner, uint256 index) external view  returns (uint256) ;

    // Returns current owner of the Booster having the ID = boosterId
    function ownerOfBooster(uint256 boosterId) external view returns (address owner) ;

    // Returns the boostURT for the Booster
    function tokenURI(uint256 boosterId) external view  returns (string memory) ;

    function baseURI() external view returns (string memory) ;

    function totalSupply() external view  returns (uint256) ;

    function tokenByIndex(uint256 index) external view  returns (uint256) ;

    // A BOOSTER owner can approve anyone to be able to transfer the underlying booster
    function approve(address to, uint256 boosterId) external ;

    // Returns the Address currently approved for the Booster with ID = boosterId
    function getApproved(uint256 boosterId) external view  returns (address);

    function setApprovalForAll(address operator, bool _approved) external;

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function safeTransferFrom(address from, address to, uint256 boosterId) external;

    function safeTransferFrom(address from, address to, uint256 boosterId, bytes memory data) external;


    function transferFrom(address from, address to, uint256 boosterId) external;


    // #############################################################
    // ######## FUNCTIONS SPECIFIC TO SIGH FINANCE BOOSTERS ########
    // #############################################################

    // Returns the number of Boosters of a particular category owned by the owner address
    function totalBoostersOwnedOfType(address owner, string memory _category) external view returns (uint256) ;

    // Returns farmer address who owns this Booster and its boosterType 
    function getBoosterInfo(uint256 boosterId) external view returns (address farmer, string memory boosterType );

    function isCategorySupported(string memory _category) external view returns (bool);

    function totalBoostersAvailable(string memory _category) external view returns (uint256);

//     function getAllBoosterTypesSupported() external view returns (string[] memory) ;

}