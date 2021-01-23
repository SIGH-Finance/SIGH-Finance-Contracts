// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {InitializableAdminUpgradeabilityProxy} from "../dependencies/upgradability/InitializableAdminUpgradeabilityProxy.sol";
import {ERC20} from "../dependencies/openzeppelin/token/ERC20/ERC20.sol";

import {IGlobalAddressesProvider} from  "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {ILendingPool} from "../../interfaces/lendingProtocol/ILendingPool.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from "./libraries/upgradability/InitializableImmutableAdminUpgradeabilityProxy.sol";


/**
* @title LendingPoolConfigurator contract
* @author Aave, SIGH Finance (modified by SIGH FINANCE)
* @notice Executes configuration methods on the LendingPoolCore contract. Allows to enable/disable instruments,
* and set different protocol parameters.
**/

contract LendingPoolConfigurator is VersionedInitializable  {

    // using SafeMath for uint256;
    IGlobalAddressesProvider public globalAddressesProvider;

    mapping (address => address) private sighStreamProxies;
// ######################
// ####### EVENTS #######
// ######################

    /**
    * @dev emitted when a instrument is initialized.
    * @param _instrument the address of the instrument
    * @param _iToken the address of the overlying iToken contract
    * @param _interestRateStrategyAddress the address of the interest rate strategy for the instrument
    **/
    event InstrumentInitialized( address indexed _instrument, address indexed _iToken, address _interestRateStrategyAddress, address sighStreamAddress, address sighStreamImplAddress );
    event InstrumentRemoved( address indexed _instrument);      // emitted when a instrument is removed.

    event BorrowingOnInstrumentSwitched(address indexed _instrument, bool switch_ );
    event StableRateOnInstrumentSwitched(address indexed _instrument, bool isEnabled);          // emitted when stable rate borrowing is switched on a instrument
    event InstrumentActivationSwitched(address indexed _instrument, bool switch_ );
    event InstrumentFreezeSwitched(address indexed _instrument, bool isFreezed);                      // emitted when a instrument is freezed

    /**
    * @dev emitted when a instrument is enabled as collateral.
    * @param _instrument the address of the instrument
    * @param _ltv the loan to value of the asset when used as collateral
    * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
    * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
    **/
    event InstrumentEnabledAsCollateral(  address indexed _instrument,  uint256 _ltv,  uint256 _liquidationThreshold,  uint256 _liquidationBonus );
    event InstrumentDisabledAsCollateral(address indexed _instrument);         // emitted when a instrument is disabled as collateral


    event InstrumentCollateralParametersUpdated(address _instrument,uint256 _ltv,  uint256 _liquidationThreshold,  uint256 _liquidationBonus );
    event InstrumentInterestRateStrategyChanged(address _instrument, address _strategy);      // emitted when a _instrument interest strategy contract is updated
    event InstrumentDecimalsUpdated(address _instrument,uint256 decimals);

    event sighStreamImplUpdated(address instrumentAddress,address newSighStreamImpl );
    event ProxyCreated(address instrument, address  sighStreamProxyAddress);

// #############################
// ####### PROXY RELATED #######
// #############################

    uint256 public constant CONFIGURATOR_REVISION = 0x1;

    function getRevision() internal override pure returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(IGlobalAddressesProvider _globalAddressesProvider) public initializer {
        globalAddressesProvider = _globalAddressesProvider;
    }

// ########################
// ####### MODIFIER #######
// ########################
    /**
    * @dev only the lending pool manager can call functions affected by this modifier
    **/
    modifier onlyLendingPoolManager {
        require( globalAddressesProvider.getLendingPoolManager() == msg.sender, "The caller must be a lending pool manager" );
        _;
    }

// ################################################################################################
// ####### INITIALIZE A NEW INSTRUMENT (Deploys a new IToken Contract for the INSTRUMENT) #########
// ################################################################################################
  /**
   * @dev Initializes an instrument reserve
   * @param iTokenImpl  The address of the iToken contract implementation
   * @param stableDebtTokenImpl The address of the stable debt token contract
   * @param variableDebtTokenImpl The address of the variable debt token contract
   * @param underlyingAssetDecimals The decimals of the reserve underlying asset
   * @param interestRateStrategyAddress The address of the interest rate strategy contract for this reserve
   **/
  function initInstrument(address iTokenImpl, address stableDebtTokenImpl, address variableDebtTokenImpl, address sighHarvesterAddressImpl, uint8 underlyingAssetDecimals, address interestRateStrategyAddress) public onlyPoolAdmin {
    address asset = ITokenConfiguration(iTokenImpl).UNDERLYING_ASSET_ADDRESS();

    require(address(pool) == ITokenConfiguration(iTokenImpl).POOL(), "INVALID ITOKEN POOL ADDRESS");
    require(address(pool) == ITokenConfiguration(stableDebtTokenImpl).POOL(), "INVALID STABLE DEBT TOKEN POOL ADDRESS");
    require(address(pool) == ITokenConfiguration(variableDebtTokenImpl).POOL(), "INVALID VARIABLE DEBT TOKEN POOL ADDRESS");
    require(asset == ITokenConfiguration(stableDebtTokenImpl).UNDERLYING_ASSET_ADDRESS(), "INVALID STABLE DEBT TOKEN UNDERLYING ADDRESS");
    require(asset == ITokenConfiguration(variableDebtTokenImpl).UNDERLYING_ASSET_ADDRESS(), "INVALID VARIABLE DEBT TOKEN UNDERLYING ADDRESS");

    address iTokenProxyAddress = _initTokenWithProxy(iTokenImpl, underlyingAssetDecimals);                          // Create a proxy contract for IToken
    address stableDebtTokenProxyAddress = _initTokenWithProxy(stableDebtTokenImpl, underlyingAssetDecimals);        // Create a proxy contract for stable Debt Token
    address variableDebtTokenProxyAddress = _initTokenWithProxy(variableDebtTokenImpl, underlyingAssetDecimals);    // Create a proxy contract for variable Debt Token
    address SIGHHarvesterProxyAddress = setSIGHHarvesterImplInternal(address(globalAddressesProvider),sighHarvesterAddressImpl, asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress );    // creates a Proxy Contract for the SIGH Harvester

    pool.initInstrument(asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress, SIGHHarvesterProxyAddress, interestRateStrategyAddress);

    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getConfiguration(asset);
    currentConfig.setDecimals(underlyingAssetDecimals);
    currentConfig.setActive(true);
    currentConfig.setFrozen(false);
    pool.setConfiguration(asset, currentConfig.data);

    emit InstrumentInitialized(asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress, SIGHHarvesterProxyAddress, interestRateStrategyAddress, underlyingAssetDecimals);
  }

    /**
    * @dev initializes an instrument
    * @param _instrument the address of the instrument to be initialized
    * @param _interestRateStrategyAddress the address of the interest rate strategy contract for this instrument
    **/
    function initInstrument( address _instrument, address iTokenInstance,  address _interestRateStrategyAddress, address sighStreamImplAddress) external onlyLendingPoolManager {
        ERC20 asset = ERC20(_instrument);

        // string memory iTokenName = string(abi.encodePacked(" Yield Farming Instrument - ", asset.name()));
        // string memory iTokenSymbol = string(abi.encodePacked("I-", asset.symbol()));
        uint8 decimals = uint8(asset.decimals());

        // Deploying IToken And Sigh Stream Contracts
        // IToken iTokenInstance = new IToken( address(globalAddressesProvider), _instrument, decimals, iTokenName, iTokenSymbol ); // DEPLOYS A NEW ITOKEN CONTRACT
        // SighStream sighStreamInstance = new SighStream();

        // creates a Proxy for the SIGH Stream Contract
        setSIGHHarvesterImplInternal(sighStreamImplAddress, _instrument, iTokenInstance );

        address sighStreamProxy = sighStreamProxies[_instrument];

        ILendingPool _lendingPool = ILendingPool(globalAddressesProvider.getLendingPool());
        _lendingPool.initInstrument( _instrument, iTokenInstance, decimals, _interestRateStrategyAddress, sighStreamProxy );

        emit InstrumentInitialized( _instrument, iTokenInstance, _interestRateStrategyAddress,  sighStreamProxy, sighStreamImplAddress  );
    }

// ###################################################################################################
// ####### FUNCTIONS WHICH INTERACT WITH LENDINGPOOL CONTRACT ####################################
// ####### --> removeInstrument() : REMOVE INSTRUMENT    #####################################
// ####### --> instrumentActivationSwitch()      :      INSTRUMENT ACTIVATION SWITCH ################################
// ####### --> instrumentBorrowingSwitch()   :   BORROWING SWITCH  #################################
// ####### --> instrumentStableBorrowRateSwitch()    :     STABLE BORROW RATE SWITCH  ################
// ####### --> enableInstrumentAsCollateral()    :   COLLATERAL RELATED  ##############################
// ####### --> disableInstrumentAsCollateral()   :   COLLATERAL RELATED  ##############################
// ####### --> instrumentFreezeSwitch()     :      FREEZE INSTRUMENT SWITCH #######################################
// ####### --> setInstrumentCollateralParameters()    :   SETTING COLLATERAL VARIABLES : [LTV, Liquidation Threshold, Liquidation Bonus]  ###########################
// ####### --> setInstrumentDecimals()               :   SETTING VARIABLES  ###########################
// ####### --> setInstrumentInterestRateStrategyAddress()     : SETTING INTEREST RATE STRATEGY  #######
// ####### --> refreshLendingPool_lendingPoolConfiguration()   :   REFRESH THE ADDRESS OF CORE  ###############
// ###################################################################################################

    // function removeInstrument( address _instrument ) external onlyLendingPoolManager {
    //     ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
    //     require(core.removeInstrument( _instrument ),"Failed to remove instrument" );
    //     emit InstrumentRemoved( _instrument );
    // }

//    /**
//    * @dev activates/deactivates a _instrument
//    * @param _instrument the address of the _instrument
//    * @param switch_  true / false to activate / deactivate
//    **/
//    function instrumentActivationSwitch(address _instrument, bool switch_) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.InstrumentActivationSwitch(_instrument, switch_);
//        emit InstrumentActivationSwitched(_instrument, switch_);
//    }
//
//    /**
//    * @dev enables borrowing on a instrument
//    * @param _instrument the address of the instrument
//    * @param borrowRateSwitch true if stable borrow rate needs to be enabled & false if it needs to be disabled
//    **/
//    function instrumentBorrowingSwitch(address _instrument, bool borrowRateSwitch) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//            core.borrowingOnInstrumentSwitch(_instrument, borrowRateSwitch );
//            emit BorrowingOnInstrumentSwitched(_instrument, borrowRateSwitch);
//    }
//
//    /**
//    * @dev switch stable rate borrowing on a instrument
//    * @param _instrument the address of the instrument
//    * @param switchStableBorrowRate true / false to enable / disable
//    **/
//    function instrumentStableBorrowRateSwitch(address _instrument,bool switchStableBorrowRate) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.instrumentStableBorrowRateSwitch(_instrument, switchStableBorrowRate);
//        emit StableRateOnInstrumentSwitched(_instrument, switchStableBorrowRate);
//    }
//
//    /**
//    * @dev enables a instrument to be used as collateral
//    * @param _instrument the address of the instrument
//    * @param _baseLTVasCollateral the loan to value of the asset when used as collateral
//    * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
//    * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
//    **/
//    function enableInstrumentAsCollateral( address _instrument, uint256 _baseLTVasCollateral, uint256 _liquidationThreshold, uint256 _liquidationBonus ) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.enableInstrumentAsCollateral( _instrument, _baseLTVasCollateral, _liquidationThreshold, _liquidationBonus );
//        emit InstrumentEnabledAsCollateral( _instrument, _baseLTVasCollateral, _liquidationThreshold, _liquidationBonus );
//    }
//
//    /**
//    * @dev disables a instrument as collateral
//    * @param _instrument the address of the instrument
//    **/
//    function disableInstrumentAsCollateral(address _instrument) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.disableInstrumentAsCollateral(_instrument);
//        emit InstrumentDisabledAsCollateral(_instrument);
//    }
//
//    /**
//    * @dev freezes an _instrument. A freezed _instrument doesn't accept any new deposit, borrow or rate swap, but can accept repayments, liquidations, rate rebalances and redeems
//    * @param _instrument the address of the _instrument
//    **/
//    function instrumentFreezeSwitch(address _instrument, bool switch_) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.InstrumentFreezeSwitch(_instrument, switch_);
//        emit InstrumentFreezeSwitched(_instrument,switch_);
//    }
//
//
//    /**
//    * @dev emitted when a _instrument loan to value is updated
//    * @param _instrument the address of the _instrument
//    * @param _ltv the new value for the loan to value
//    **/
//    function setInstrumentCollateralParameters(address _instrument, uint256 _ltv, uint256 _threshold, uint256 _bonus) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.updateInstrumentCollateralParameters(_instrument, _ltv, _threshold, _bonus);
//        emit InstrumentCollateralParametersUpdated(_instrument, _ltv, _threshold, _bonus);
//    }
//
//
//    /**
//    * @dev sets the interest rate strategy of a _instrument
//    * @param _instrument the address of the _instrument
//    * @param _rateStrategyAddress the new address of the interest strategy contract
//    **/
//    function setInstrumentInterestRateStrategyAddress(address _instrument, address _rateStrategyAddress) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.setInstrumentInterestRateStrategyAddress(_instrument, _rateStrategyAddress);
//        emit InstrumentInterestRateStrategyChanged(_instrument, _rateStrategyAddress);
//    }
//
//    function setInstrumentDecimals(address _instrument, uint decimals) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.setInstrumentDecimals(_instrument, decimals);
//        emit InstrumentDecimalsUpdated(_instrument, decimals);
//    }
//
//
//    // refreshes the lending pool core configuration to update the cached address
//    function refreshLendingPoolCoreConfiguration() external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        core.refreshConfiguration();
//    }
//
////   // refreshes the lending pool configuration to update the cached address
//    function refreshLendingPoolConfiguration() external onlyLendingPoolManager {
//        ILendingPool lendingPool = ILendingPool(globalAddressesProvider.getLendingPool());
//        lendingPool.refreshConfig();
//    }
//
////   // Changes SIGH Stream Contract For an Instrument
//    function updateSIGHStreamForInstrument(  address newSighStreamImpl, address instrumentAddress, address iTokenAddress) external onlyLendingPoolManager {
//        ILendingPool core = ILendingPool(globalAddressesProvider.getLendingPool());
//        require(core.getInstrumentITokenAddress(instrumentAddress) == iTokenAddress,"Wrong instrument - IToken addresses provided");
//        updateSIGHHarvesterImplInternal(newSighStreamImpl,instrumentAddress,iTokenAddress);
//        emit sighStreamImplUpdated(instrumentAddress,newSighStreamImpl );
//    }
//
//    function getSighStreamAddress(address instrumentAddress) external view returns (address sighStreamProxyAddress) {
//        return sighStreamProxies[instrumentAddress];
//    }

// #############################################
// ######  FUNCTION TO UPGRADE THE PROXY #######
// #############################################

    function setSIGHHarvesterImplInternal( address globalAddressProvider, address sighHarvesterAddressImpl, address asset, address iTokenProxyAddress, address stableDebtTokenProxyAddress, address variableDebtTokenProxyAddress ) internal {

        bytes memory params = abi.encodeWithSignature("initialize(address,address,address,address,address)", globalAddressProvider, asset, iTokenAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress );            // initialize function is called in the new implementation contract
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        proxy.initialize(sighHarvesterAddressImpl, address(this), params);
        sighStreamProxies[asset] = address(proxy);
        emit ProxyCreated(asset, address(proxy));
    }

    function updateSIGHHarvesterImplInternal(address _sighStreamAddress, address instrumentAddress, address iTokenAddress ) internal {
        // Proxy Contract Address
        address payable proxyAddress = address(uint160(sighStreamProxies[instrumentAddress] ));
        InitializableAdminUpgradeabilityProxy proxy = InitializableAdminUpgradeabilityProxy(proxyAddress);
        bytes memory params = abi.encodeWithSignature("initialize(address,address,address)", address(globalAddressesProvider),instrumentAddress,iTokenAddress );            // initialize function is called in the new implementation contract
        proxy.upgradeToAndCall(_sighStreamAddress, params);
    }






  function _initTokenWithProxy(address implementation, uint8 decimals) internal returns (address) {
    InitializableImmutableAdminUpgradeabilityProxy proxy = new InitializableImmutableAdminUpgradeabilityProxy(address(this));
    bytes memory params = abi.encodeWithSignature( 'initialize(uint8,string,string)', decimals, IERC20Detailed(implementation).name(), IERC20Detailed(implementation).symbol() );
    proxy.initialize(implementation, params);
    return address(proxy);
  }

  function _upgradeTokenImplementation(address asset, address proxyAddress, address implementation) internal {
    InitializableImmutableAdminUpgradeabilityProxy proxy = InitializableImmutableAdminUpgradeabilityProxy(payable(proxyAddress));
    DataTypes.InstrumentConfigurationMap memory configuration = pool.getConfiguration(asset);

    (, , , uint256 decimals, ) = configuration.getParamsMemory();
    bytes memory params = abi.encodeWithSignature('initialize(uint8,string,string)', uint8(decimals), IERC20Detailed(implementation).name(), IERC20Detailed(implementation).symbol());
    proxy.upgradeToAndCall(implementation, params);
  }

  function _checkNoLiquidity(address asset) internal view {
    DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
    uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(instrumentData.iTokenAddress);
    require(availableLiquidity == 0 && instrumentData.currentLiquidityRate == 0, "Instrument LIQUIDITY NOT 0");
  }






}