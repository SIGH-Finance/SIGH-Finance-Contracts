// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.7.0;

import "../dependencies/openzeppelin/token/ERC721/IERC721Metadata.sol";
import "../dependencies/openzeppelin/token/ERC721/IERC721Enumerable.sol";
import "../dependencies/openzeppelin/token/ERC721/IERC721Receiver.sol";

import "../dependencies/openzeppelin/introspection/ERC165.sol";
import "../dependencies/openzeppelin/access/Ownable.sol";
import "../dependencies/openzeppelin/utils/Counters.sol";
import "../dependencies/openzeppelin/math/SafeMath.sol";
import "../dependencies/openzeppelin/utils/Address.sol";
import "../dependencies/openzeppelin/utils/Strings.sol";

import "../dependencies/BoostersDependencies/BoostersEnumerableSet.sol";
import "../dependencies/BoostersDependencies/BoostersEnumerableMap.sol";
import "../dependencies/BoostersDependencies/BoostersStringUtils.sol";

import "../../interfaces/NFTBoosters/ISIGHBoosters.sol";


contract SIGHBoosters is ISIGHBoosters, ERC165,IERC721Metadata,IERC721Enumerable, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _boosterIds;

    using SafeMath for uint256;
    using Address for address;
    using BoostersEnumerableSet for BoostersEnumerableSet.BoosterSet;
    using BoostersEnumerableMap for BoostersEnumerableMap.UintToNFTMap;
    using Strings for uint256;
    using BoostersStringUtils for string;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    string private _name;
    string private _symbol;
    mapping (uint256 => string) private _BoostURIs;
    string private _baseURI;

    struct boosterCategory {
        bool isSupported;
        uint256 totalBoosters;
        uint256 _platformFeeDiscount;
        uint256 _sighPayDiscount;
    }

    mapping (string => boosterCategory) private boosterCategories;
    mapping (string => uint256) private totalBoosters;      // (Booster Category => boosters Available) Mapping
    mapping (uint256 => string) private _BoosterCategory;
    mapping (uint256 => address) private _BoosterApprovals;                       // Mapping from BoosterID to approved address
    mapping (address => mapping (address => bool)) private _operatorApprovals;    // Mapping from owner to operator approvals
   
    mapping (address => BoostersEnumerableSet.BoosterSet) private farmersWithBoosts;     // Mapping from holder address to their (enumerable) set of owned tokens & categories
    BoostersEnumerableMap.UintToNFTMap private boostersData;                    // Enumerable mapping from token ids to their owners & categories


    constructor(string memory name_, string memory symbol_)  {
        _name = name_;
        _symbol = symbol_;

        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }


    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    function createNewSIGHBooster(address _owner, string memory _type,  string memory boosterURI, bytes memory _data) public override onlyOwner returns (uint256) {
        require(boosterCategories[_type].isSupported,'Not a valid Booster Type');

        _boosterIds.increment();
        uint256 newItemId = _boosterIds.current();

        _safeMint(_owner, newItemId, _type,_data);
        _setBoosterURI(newItemId,boosterURI);
        _setType(newItemId,_type);

        boosterCategories[_type].totalBoosters = boosterCategories[_type].totalBoosters.add(1);

        return newItemId;
    }

    function addNewBoosterType(string memory _type, uint256 _platformFeeDiscount_, uint256 _sighPayDiscount_) public override onlyOwner returns (bool) {
        require(!boosterCategories[_type].isSupported,"SIGH BOOSTERS: Booster Type already exists");
        require(_platformFeeDiscount_ > 0,"SIGH BOOSTERS: Platform Fee Discount cannot be 0");
        require(_sighPayDiscount_ > 0,"SIGH BOOSTERS: SIGH Pay Fee Discount cannot be 0");
        boosterCategories[_type] =  boosterCategory({isSupported: true, totalBoosters:0, _platformFeeDiscount: _platformFeeDiscount_, _sighPayDiscount: _sighPayDiscount_  });
        return true;
    }

    function updateBoosterURI(uint256 boosterId, string memory boosterURI )  public override onlyOwner returns (bool) {
        require(_exists(boosterId), "SIGH BOOSTERS: URI set of nonexistent token");
        _setBoosterURI(boosterId,boosterURI);
        return true;
     }

    function updateDiscountMultiplier(string memory _type, uint256 _platformFeeDiscount_,uint256 _sighPayDiscount_)  public onlyOwner returns (bool) {
        require(!boosterCategories[_type].isSupported,"SIGH BOOSTERS: Booster Type doesn't exist");
        require(_platformFeeDiscount_ > 0,"SIGH BOOSTERS: Platform Fee Discount cannot be 0");
        require(_sighPayDiscount_ > 0,"SIGH BOOSTERS: SIGH Pay Fee Discount cannot be 0");
        boosterCategories[_type]._platformFeeDiscount = _platformFeeDiscount_;
        boosterCategories[_type]._sighPayDiscount = _sighPayDiscount_;
        return true;
     }

    // ###########################################
    // ######## STANDARD ERC721 FUNCTIONS ########
    // ###########################################

    function name() public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        return _symbol;
    }

    // Returns total number of Boosters owned by the _owner
    function balanceOf(address _owner) external view override(IERC721,ISIGHBoosters) returns (uint256 balance) {
        require(_owner != address(0), "ERC721: balance query for the zero address");
        return farmersWithBoosts[_owner].length();
    }

    //  See {IERC721Enumerable-tokenOfOwnerByIndex}.
    function tokenOfOwnerByIndex(address owner, uint256 index) public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256 id) {
        BoostersEnumerableSet.ownedBooster memory _booster = farmersWithBoosts[owner].at(index);
        return _booster.boostId;
    }

    // Returns current owner of the Booster having the ID = boosterId
    function ownerOf(uint256 boosterId) public view override returns (address owner) {
         owner =  ownerOfBooster(boosterId);
         return owner;
    }

    // Returns current owner of the Booster having the ID = boosterId
    function ownerOfBooster(uint256 boosterId) public view override returns (address owner) {
         ( owner, ) =  boostersData.get(boosterId);
         return owner;
    }

    // Returns the boostURI for the Booster
    function tokenURI(uint256 boosterId) public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        require(_exists(boosterId), "URI query for nonexistent SIGH Booster");
        string memory _boostURI = _BoostURIs[boosterId];
        
        if (bytes(_baseURI).length == 0) {                                  // If there is no base URI, return the token URI.
            return _boostURI;
        }

        if (bytes(_boostURI).length > 0) {                                  // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
            return string(abi.encodePacked(_baseURI, _boostURI));
        }
        
        return string(abi.encodePacked(_baseURI, boosterId.toString()));    // If there is a baseURI but no tokenURI, concatenate the boosterId to the baseURI.
    }

    function baseURI() public view override returns (string memory) {
        return _baseURI;
    }

    function totalSupply() public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256) {
        return boostersData.length();
    }

    function tokenByIndex(uint256 index) public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256) {
        (uint256 _boostId, , ) = boostersData.at(index);
        return _boostId;
    }

    // A BOOSTER owner can approve anyone to be able to transfer the underlying booster
    function approve(address to, uint256 boosterId) override(IERC721,ISIGHBoosters) external {
        address _owner = ownerOfBooster(boosterId);
        require(to != _owner, "SIGH BOOSTERS: Approval to current owner");
        require(_msgSender() == _owner || isApprovedForAll(_owner, _msgSender()),"SIGH BOOSTERS: Caller is not the owner nor approved for all Boosters owned by the owner");
        _approve(to, boosterId);
    }

    // Returns the Address currently approved for the Booster with ID = boosterId
    function getApproved(uint256 boosterId) public view override(IERC721,ISIGHBoosters) returns (address) {
        require(_exists(boosterId), "SIGH BOOSTERS: Approved query for nonexistent Booster");
        return _BoosterApprovals[boosterId];
    }

    function setApprovalForAll(address operator, bool _approved) public virtual override(IERC721,ISIGHBoosters) {
        require(operator != _msgSender(), "SIGH BOOSTERS: Caller cannot be Approved");
        _operatorApprovals[_msgSender()][operator] = _approved;
        emit ApprovalForAll(_msgSender(), operator, _approved);
    }

    function isApprovedForAll(address owner, address operator) public view override(IERC721,ISIGHBoosters) returns (bool) {
        _operatorApprovals[owner][operator];
        return true;
    }

    function safeTransferFrom(address from, address to, uint256 boosterId)  public virtual override(IERC721,ISIGHBoosters) {
        safeTransferFrom(from, to, boosterId, "");
    }

    function safeTransferFrom(address from, address to, uint256 boosterId, bytes memory data) public virtual override(IERC721,ISIGHBoosters) {
        require(_isApprovedOrOwner(_msgSender(), boosterId), "SIGH BOOSTERS: Transfer caller is not owner nor approved");
        _safeTransfer(from, to, boosterId, data);
    }


    function transferFrom(address from, address to, uint256 boosterId) public virtual override(IERC721,ISIGHBoosters) {
        require(_isApprovedOrOwner(_msgSender(), boosterId), "SIGH BOOSTERS: Transfer caller is not owner nor approved");
        _transfer(from, to, boosterId);
    }


    // #############################################################
    // ######## FUNCTIONS SPECIFIC TO SIGH FINANCE BOOSTERS ########
    // #############################################################

    // Returns the number of Boosters of a particular category owned by the owner address
    function totalBoostersOwnedOfType(address owner, string memory _category) external view override returns (uint) {
        require(owner != address(0), "SIGH BOOSTERS: balance query for the zero address");
        require(boosterCategories[_category].isSupported, "Not a valid Booster Type");

        BoostersEnumerableSet.BoosterSet storage boostersOwned = farmersWithBoosts[owner];

        if (boostersOwned.length() == 0) {
            return 0;
        }

        uint ans;

        for (uint32 i=1; i <= boostersOwned.length(); i++ ) {
            BoostersEnumerableSet.ownedBooster memory _booster = boostersOwned.at(i);
            if ( _booster._type.equal(_category) ) {
                ans = ans + 1;
            }
        }

        return ans ;
    }

    // Returns farmer address who owns this Booster and its boosterType 
    function getBoosterInfo(uint256 boosterId) external view override returns (address farmer, string memory boosterType ) {
         ( farmer, boosterType ) =  boostersData.get(boosterId);
    }

    function isCategorySupported(string memory _category) external view override returns (bool) {
        return boosterCategories[_category].isSupported;
    }

    function totalBoostersAvailable(string memory _category) external view override returns (uint256) {
        return boosterCategories[_category].totalBoosters;
    }

    

    // get Booster Type
    function getBoosterCategory(uint256 boosterId) public view returns ( string memory boosterType ) {
         ( , boosterType ) =  boostersData.get(boosterId);
    }

    // get Booster Discount Multiplier
    function getDiscountRatiosForBooster(uint256 boosterId) external view returns ( uint platformFeeDiscount, uint sighPayDiscount ) {
        require(!_exists(boosterId), "SIGH BOOSTERS: Booster doesn't exist");
        platformFeeDiscount =  boosterCategories[getBoosterCategory(boosterId)]._platformFeeDiscount;
        sighPayDiscount =  boosterCategories[getBoosterCategory(boosterId)]._sighPayDiscount;
    }

    function isValidBooster(uint256 boosterId) external view returns (bool) {
        return _exists(boosterId);
    }







    // #####################################
    // ######## INTERNAL FUNCTIONS  ########
    // #####################################

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 boosterId, string memory _typeOfBoost, bytes memory _data) internal {
        _mint(to, boosterId, _typeOfBoost);
        require(_checkOnERC721Received(address(0), to, boosterId, _data), "SIGH BOOSTERS: transfer to non ERC721Receiver implementer");
    }


    /**
     * @dev Mints `boosterId` and transfers it to `to`.
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     */
    function _mint(address to, uint256 boosterId, string memory _typeOfBoost) internal  {
        require(to != address(0), "SIGH BOOSTERS: Cannot mint Booster to the zero address");
        require(!_exists(boosterId), "SIGH BOOSTERS: Booster already minted");

        BoostersEnumerableSet.ownedBooster memory newBooster = BoostersEnumerableSet.ownedBooster({ boostId: boosterId, _type: _typeOfBoost });
        BoostersEnumerableMap.boosterInfo memory newBoosterInfo = BoostersEnumerableMap.boosterInfo({ owner: to, _type: _typeOfBoost });

        farmersWithBoosts[to].add(newBooster);
        boostersData.set(boosterId, newBoosterInfo);

        emit Transfer(address(0), to, boosterId);
    }

    /**
     * @dev Returns whether `boosterId` exists.
     */
    function _exists(uint256 boosterId) internal view returns (bool) {
        return boostersData.contains(boosterId);
    }


    /**
     * @dev Sets `_boosterURI` as the boosterURI of `boosterId`.
     *
     * Requirements:
     *
     * - `boosterId` must exist.
     */
    function _setBoosterURI(uint256 boosterId, string memory _boosterURI) internal  {
        require(_exists(boosterId), "SIGH BOOSTERS: URI cannot be set for non-existent SIGH Booster");
        _BoostURIs[boosterId] = _boosterURI;
    }

    function _setType(uint256 boosterId, string memory _type) internal virtual {
        require(_exists(boosterId), "SIGH BOOSTERS: Type cannot be set for non-existent SIGH Booster");
        _BoosterCategory[boosterId] = _type;
    }


    function _approve(address to, uint256 boosterId) private {
        _BoosterApprovals[boosterId] = to;
        emit Approval(ownerOfBooster(boosterId), to, boosterId);
    }

    // Returns whether `spender` is allowed to manage `tokenId`.
    function _isApprovedOrOwner(address spender, uint256 boosterId) internal view returns (bool) {
        require(_exists(boosterId), "SIGH BOOSTERS: Operator query for nonexistent Booster");
        address owner = ownerOfBooster(boosterId);
        return (spender == owner || getApproved(boosterId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeTransfer(address from, address to, uint256 boosterId, bytes memory _data) internal virtual {
        _transfer(from, to, boosterId);
        require(_checkOnERC721Received(from, to, boosterId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _transfer(address from, address to, uint256 boosterId) internal virtual {
        require(ownerOfBooster(boosterId) == from, "SIGH BOOSTERS: Transfer of token that is not owned");
        require(to != address(0), "SIGH BOOSTERS: Transfer to the zero address");

//        _beforeTokenTransfer(from, to, boosterId);
        _approve(address(0), boosterId);          // Clear approvals from the previous owner
        
        BoostersEnumerableSet.ownedBooster memory _ownedBooster = BoostersEnumerableSet.ownedBooster({boostId: boosterId, _type: _BoosterCategory[boosterId] });

        farmersWithBoosts[from].remove(_ownedBooster);
        farmersWithBoosts[to].add(_ownedBooster);

        BoostersEnumerableMap.boosterInfo memory _boosterInfo = BoostersEnumerableMap.boosterInfo({owner: to, _type: _BoosterCategory[boosterId] });
        boostersData.set(boosterId, _boosterInfo);

        emit Transfer(from, to, boosterId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param boosterId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 boosterId, bytes memory _data) private returns (bool) {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector( IERC721Receiver(to).onERC721Received.selector, _msgSender(), from, boosterId, _data ), "ERC721: transfer to non ERC721Receiver implementer");
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

//    /**
//     * @dev Hook that is called before any token transfer.
//    */
//    function _beforeTokenTransfer(address from, address to, uint256 boosterId) internal virtual { }


}