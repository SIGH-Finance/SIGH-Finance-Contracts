// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../dependencies/openzeppelin/math/SafeMath.sol";
import {IERC20} from "../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../dependencies/openzeppelin/token/ERC20/SafeERC20.sol";
import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {Address} from '../dependencies/openzeppelin/utils/Address.sol';

import {IFlashLoanReceiver} from "./flashLoan/interfaces/IFlashLoanReceiver.sol";

import {ILendingPool} from "../../interfaces/lendingProtocol/ILendingPool.sol";
import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";

import {ISIGHHarvestDebtToken} from '../../interfaces/lendingProtocol/ISIGHHarvestDebtToken.sol';
import {IIToken} from '../../interfaces/lendingProtocol/IIToken.sol';
import {IVariableDebtToken} from "../../interfaces/lendingProtocol/IVariableDebtToken.sol";
import {IStableDebtToken} from '../../interfaces/lendingProtocol/IStableDebtToken.sol';
import {IFeeProviderLendingPool} from "../../interfaces/lendingProtocol/IFeeProviderLendingPool.sol";
import {ISIGHVolatilityHarvesterLendingPool} from "../../interfaces/lendingProtocol/ISIGHVolatilityHarvesterLendingPool.sol";
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';


import {Helpers} from './libraries/helpers/Helpers.sol';
import {WadRayMath} from './libraries/math/WadRayMath.sol';
import {PercentageMath} from './libraries/math/PercentageMath.sol';
import {InstrumentReserveLogic} from './libraries/logic/InstrumentReserveLogic.sol';
import {GenericLogic} from './libraries/logic/GenericLogic.sol';
import {ValidationLogic} from './libraries/logic/ValidationLogic.sol';
import {InstrumentConfiguration} from './libraries/configuration/InstrumentConfiguration.sol';
import {UserConfiguration} from './libraries/configuration/UserConfiguration.sol';
import {DataTypes} from './libraries/types/DataTypes.sol';
import {LendingPoolStorage} from './LendingPoolStorage.sol';


/**
 * @title LendingPool contract
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Swap their loans between variable and stable rate
 *   # Enable/disable their deposits as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract
 * - All admin functions are callable by the LendingPoolConfigurator contract
 * @author Aave, _astromartian
 **/
contract LendingPool is VersionedInitializable, ILendingPool, LendingPoolStorage {

  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  using InstrumentReserveLogic for DataTypes.InstrumentData;
  using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;


  //main configuration parameters
  uint256 public constant MAX_STABLE_RATE_BORROW_SIZE_PERCENT = 2500;
  uint256 public constant FLASHLOAN_PREMIUM_TOTAL = 9;
  uint256 public constant _MAX_NUMBER_INSTRUMENTS = 128;
  uint256 public constant LENDINGPOOL_REVISION = 0x1;

  modifier whenNotPaused() {
    _whenNotPaused();
    _;
  }

  modifier onlyLendingPoolConfigurator() {
    require(addressesProvider.getLendingPoolConfigurator() == msg.sender, "Caller not Lending Pool Configurator");
    _;
  }

  function _whenNotPaused() internal view {
    require(!_paused, "Lending Pool is Paused");
  }
    
  function getRevision() internal pure override returns (uint256) {
    return LENDINGPOOL_REVISION;
  }

  /**
   * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
   * LendingPoolAddressesProvider of the market.
   * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
   *   on subsequent operations
   * @param provider The address of the LendingPoolAddressesProvider
   **/
  function initialize(IGlobalAddressesProvider provider) public initializer {
    addressesProvider = provider;
  }

  function refreshConfig() external override onlyLendingPoolConfigurator {
    refreshConfigInternal() ;
  }

  function refreshConfigInternal() internal {
    sighVolatilityHarvester = ISIGHVolatilityHarvesterLendingPool(addressesProvider.getSIGHVolatilityHarvester()) ;
    sighPayAggregator = addressesProvider.getSIGHPAYAggregator() ;
    platformFeeCollector = addressesProvider.getSIGHFinanceFeeCollector();

    feeProvider = IFeeProviderLendingPool(addressesProvider.getFeeProvider());
  }


// ###########################################
// ######  DEPOSIT and REDEEM FUNCTIONS ######
// ###########################################

    /**
    * @dev deposits The underlying asset into the instrument. A corresponding amount of the overlying asset (ITokens) is minted.
    * @param _instrument the address of the underlying instrument (to be deposited)
    * @param _amount the amount to be deposited
    * @param boosterId boosterId is provided by the caller if he owns a SIGH Booster NFT to get discount on the Deposit Fee
    **/
    function deposit( address _instrument, uint256 _amount, uint256 boosterId ) external override whenNotPaused  {

        DataTypes.InstrumentData storage instrument =_instruments[_instrument];
        ValidationLogic.validateDeposit(instrument, _amount);  // checks if the instrument is active and not frozen                     // Makes the deposit checks

        address iToken = instrument.iTokenAddress;

        // Split Deposit fee in Reserve Fee and Platform Fee. Calculations based on the discount (if any) provided by the boosterId
        (uint256 totalFee, uint256 platformFee, uint256 reserveFee) = feeProvider.calculateDepositFee(msg.sender,_instrument, _amount, boosterId);
        if (platformFee > 0 && platformFeeCollector != address(0) ) {
            IERC20(_instrument).safeTransferFrom( msg.sender, platformFeeCollector, platformFee );
        }
        if (reserveFee > 0 && sighPayAggregator  != address(0) ) {
            IERC20(_instrument).safeTransferFrom( msg.sender, sighPayAggregator, reserveFee );
        }

        sighVolatilityHarvester.updateSIGHSupplyIndex(_instrument);  // Update SIGH Supply Index                  // Update SIGH Liquidity Index for Instrument
        instrument.updateState(sighPayAggregator);
        instrument.updateInterestRates(_instrument, iToken, _amount.sub(totalFee), 0);

        IERC20(_instrument).safeTransferFrom(msg.sender, iToken, _amount.sub(totalFee)); // Transfer the Deposit amount
        bool isFirstDeposit = IIToken(iToken).mint(msg.sender, _amount.sub(totalFee) , instrument.liquidityIndex); // Mint the ITokens

        if (isFirstDeposit) {
            _usersConfig[msg.sender].setUsingAsCollateral(instrument.id, true);
            emit InstrumentUsedAsCollateralEnabled(_instrument, msg.sender);
        }

        emit Deposit(_instrument, msg.sender,  _amount.sub(totalFee), platformFee, reserveFee, boosterId );
    }






    /**
    * @dev Withdraws the underlying amount of assets requested by _user.
    * This function is executed by the overlying IToken contract in response to a redeem action.
    * @param _instrument the address of the instrument (underlying instrument address)
    * @param amount the underlying amount to be redeemed
   * @param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a  different wallet
    **/
    function withdraw( address _instrument, uint256 amount, address to) external override whenNotPaused returns(uint256) {

        DataTypes.InstrumentData storage instrument =_instruments[_instrument];
        address iToken = instrument.iTokenAddress;

        uint256 userBalance = IIToken(iToken).balanceOf(msg.sender);
        uint256 amountToWithdraw = amount;

        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        ValidationLogic.validateWithdraw( _instrument, amountToWithdraw, userBalance,_instruments, _usersConfig[msg.sender],_instrumentsList,_instrumentsCount, addressesProvider.getPriceOracle() );

        instrument.updateState(sighPayAggregator);
        instrument.updateInterestRates(_instrument, iToken, 0, amountToWithdraw);
        sighVolatilityHarvester.updateSIGHSupplyIndex(_instrument);                    // Update SIGH Liquidity Index for Instrument

        if (amountToWithdraw == userBalance) {
            _usersConfig[msg.sender].setUsingAsCollateral(instrument.id, false);
            emit InstrumentUsedAsCollateralDisabled(_instrument, msg.sender);
        }

        IIToken(iToken).burn(msg.sender, to, amountToWithdraw, instrument.liquidityIndex);

        emit Withdraw(_instrument, msg.sender, to, amountToWithdraw);

        return amountToWithdraw;
    }

// #########################################
// ######  BORROW and REPAY FUNCTIONS ######
// #########################################

  /**
   * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
   * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
   * corresponding debt token (StableDebtToken or VariableDebtToken)
   * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
   *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
   * @param asset The address of the underlying asset to borrow
   * @param amount The amount to be borrowed
   * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
   * @param boosterId BoosterId of the Booster owned by the caller
   * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
   * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator if he has been given credit delegation allowance
   **/
  function borrow( address asset, uint256 amount, uint256 interestRateMode, uint16 boosterId, address onBehalfOf ) external override whenNotPaused {
        DataTypes.InstrumentData storage instrument =_instruments[asset];

        _executeBorrow( ExecuteBorrowParams( asset, msg.sender, onBehalfOf, amount, interestRateMode, instrument.iTokenAddress,0,0, boosterId, true) );
  }


  struct RepayVars {
      DataTypes.InterestRateMode interestRateMode;
      uint256 platformFee;
      uint256 platformFeePay;
      uint256 reserveFee;
      uint256 reserveFeePay;
      uint256 stableDebt;
      uint256 variableDebt;
      uint256 paybackAmount;
  }


  /**
   * @notice Repays a borrowed `amount` on a specific instrument reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
   * @param asset The address of the borrowed underlying asset previously borrowed
   * @param amount The amount to repay
   * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
   * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
   * user calling the function if he wants to reduce/remove his own debt, or the address of any other other borrower whose debt should be removed
   * @return The final amount repaid
   **/
    function repay( address asset, uint256 amount, uint256 rateMode, address onBehalfOf ) external override whenNotPaused returns (uint256) {
        DataTypes.InstrumentData storage instrument =_instruments[asset];
        RepayVars memory vars;

        (vars.stableDebt, vars.variableDebt) = Helpers.getUserCurrentDebt(onBehalfOf, instrument);
        vars.interestRateMode = DataTypes.InterestRateMode(rateMode);

        ValidationLogic.validateRepay(  instrument, amount, vars.interestRateMode, onBehalfOf, vars.stableDebt, vars.variableDebt);
        vars.paybackAmount = vars.interestRateMode == DataTypes.InterestRateMode.STABLE ? vars.stableDebt : vars.variableDebt;

        // getting platfrom Fee based on if it is a Stable rate loan or variable rate loan
        vars.platformFee = vars.interestRateMode == DataTypes.InterestRateMode.STABLE ?
                                                ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).getPlatformFee(onBehalfOf) :
                                                ISIGHHarvestDebtToken(instrument.variableDebtTokenAddress).getPlatformFee(onBehalfOf);

        // getting reserve Fee based on if it is a Stable rate loan or variable rate loan
        vars.reserveFee = vars.interestRateMode == DataTypes.InterestRateMode.STABLE ?
                                                ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).getReserveFee(onBehalfOf) :
                                                ISIGHHarvestDebtToken(instrument.variableDebtTokenAddress).getReserveFee(onBehalfOf);

        vars.paybackAmount = vars.paybackAmount.add(vars.platformFee).add(vars.reserveFee);    // Max payback that needs to be made

        if (amount < vars.paybackAmount) {
            vars.paybackAmount = amount;
        }

        // PAY PLATFORM FEE
        if ( vars.platformFee > 0) {
            vars.platformFeePay =  vars.paybackAmount >= vars.platformFee ? vars.platformFee : vars.paybackAmount;
            IERC20(asset).safeTransferFrom( msg.sender, platformFeeCollector, vars.platformFeePay );   // Platform Fee transferred
            vars.paybackAmount = vars.paybackAmount.sub(vars.platformFeePay);  // Update payback amount
            ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).updatePlatformFee(onBehalfOf,0,vars.platformFeePay);
        }

        // PAY RESERVE FEE
        if (vars.reserveFee > 0 && vars.paybackAmount > 0) {
            vars.reserveFeePay =  vars.paybackAmount > vars.reserveFee ? vars.reserveFee : vars.paybackAmount;
            IERC20(asset).safeTransferFrom( msg.sender, sighPayAggregator, vars.reserveFeePay );       // Reserve Fee transferred
            vars.paybackAmount = vars.paybackAmount.sub(vars.reserveFeePay);  // Update payback amount
            ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).updateReserveFee(onBehalfOf,0,vars.reserveFeePay);
        }

        instrument.updateState(sighPayAggregator);
        sighVolatilityHarvester.updateSIGHBorrowIndex(asset);                    // Update SIGH Borrow Index for Instrument

        if (vars.paybackAmount > 0) {
            if (vars.interestRateMode == DataTypes.InterestRateMode.STABLE) {
                IStableDebtToken(instrument.stableDebtTokenAddress).burn(onBehalfOf, vars.paybackAmount);
            }
            else {
                IVariableDebtToken(instrument.variableDebtTokenAddress).burn( onBehalfOf, vars.paybackAmount, instrument.variableBorrowIndex );
            }
        }
        else {
            emit Repay(asset, onBehalfOf, msg.sender, vars.platformFeePay, vars.reserveFeePay, vars.paybackAmount);
            return vars.paybackAmount.add(vars.platformFeePay).add(vars.reserveFeePay);
        }


        address iToken = instrument.iTokenAddress;
        instrument.updateInterestRates(asset, iToken, vars.paybackAmount, 0);

        if (vars.stableDebt.add(vars.variableDebt).sub(vars.paybackAmount) == 0) {
            _usersConfig[onBehalfOf].setBorrowing(instrument.id, false);
        }

        IERC20(asset).safeTransferFrom(msg.sender, iToken, vars.paybackAmount);

        emit Repay(asset, onBehalfOf, msg.sender, vars.platformFeePay, vars.reserveFeePay, vars.paybackAmount);

        return vars.paybackAmount.add(vars.platformFeePay).add(vars.reserveFeePay);
  }

// ####################################################################
// ######  1. SWAP BETWEEN STABLE AND VARIABLE BORROW RATE MODES ######
// ######  2. REBALANCES THE STABLE INTEREST RATE OF A USER      ######
// ####################################################################

  /**
   * @dev Allows a borrower to swap his debt between stable and variable mode, or viceversa
   * @param asset The address of the underlying asset borrowed
   * @param rateMode The rate mode that the user wants to swap to
   **/
  function swapBorrowRateMode(address asset, uint256 rateMode) external override whenNotPaused {
    DataTypes.InstrumentData storage instrument =_instruments[asset];

    (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(msg.sender, instrument);
    DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

    ValidationLogic.validateSwapRateMode( instrument, _usersConfig[msg.sender], stableDebt, variableDebt, interestRateMode);

    instrument.updateState(sighPayAggregator);
    sighVolatilityHarvester.updateSIGHBorrowIndex(asset);                    // Update SIGH Borrow Index for Instrument

    if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
      IStableDebtToken(instrument.stableDebtTokenAddress).burn(msg.sender, stableDebt);
      IVariableDebtToken(instrument.variableDebtTokenAddress).mint( msg.sender, msg.sender, stableDebt, instrument.variableBorrowIndex );
    }
    else {
      IVariableDebtToken(instrument.variableDebtTokenAddress).burn( msg.sender, variableDebt, instrument.variableBorrowIndex);
      IStableDebtToken(instrument.stableDebtTokenAddress).mint( msg.sender, msg.sender, variableDebt, instrument.currentStableBorrowRate);
    }

    instrument.updateInterestRates(asset, instrument.iTokenAddress, 0, 0);
    sighVolatilityHarvester.updateSIGHBorrowIndex(asset);                    // Update SIGH Borrow Index for Instrument

    emit Swap(asset, msg.sender, rateMode);
  }

  /**
   * @dev Rebalances the stable interest rate of a user to the current stable rate defined on the instrument reserve.
   * - Users can be rebalanced if the following conditions are satisfied:
   *     1. Usage ratio is above 95%
   *     2. the current deposit APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too much has been
   *        borrowed at a stable rate and depositors are not earning enough
   * @param asset The address of the underlying asset borrowed
   * @param user The address of the user to be rebalanced
   **/
  function rebalanceStableBorrowRate(address asset, address user) external override whenNotPaused {
    DataTypes.InstrumentData storage instrument =_instruments[asset];

    IERC20 stableDebtToken = IERC20(instrument.stableDebtTokenAddress);
    IERC20 variableDebtToken = IERC20(instrument.variableDebtTokenAddress);
    address iTokenAddress = instrument.iTokenAddress;

    uint256 stableDebt = IERC20(stableDebtToken).balanceOf(user);

    ValidationLogic.validateRebalanceStableBorrowRate(instrument,asset,stableDebtToken,variableDebtToken,iTokenAddress);
    instrument.updateState(sighPayAggregator);
    sighVolatilityHarvester.updateSIGHBorrowIndex(asset);                    // Update SIGH Borrow Index for Instrument

    IStableDebtToken(address(stableDebtToken)).burn(user, stableDebt);
    IStableDebtToken(address(stableDebtToken)).mint(user,user,stableDebt, instrument.currentStableBorrowRate);

    instrument.updateInterestRates(asset, iTokenAddress, 0, 0);
    sighVolatilityHarvester.updateSIGHBorrowIndex(asset);                    // Update SIGH Borrow Index for Instrument

    emit RebalanceStableBorrowRate(asset, user);
  }

// #####################################################################################################
// ######  1. DEPOSITORS CAN ENABLE DISABLE SPECIFIC DEPOSIT AS COLLATERAL                  ############
// ######  2. FUNCTION WHICH CAN BE INVOKED TO LIQUIDATE AN UNDERCOLLATERALIZED POSITION    ############
// #####################################################################################################

    /**
    * @dev allows depositors to enable or disable a specific deposit as collateral.
    * @param asset the address of the instrument
    * @param useAsCollateral true if the user wants to user the deposit as collateral, false otherwise.
    **/
    function setUserUseInstrumentAsCollateral(address asset, bool useAsCollateral) external override whenNotPaused {
        DataTypes.InstrumentData storage instrument = _instruments[asset];

        ValidationLogic.validateSetUseInstrumentAsCollateral(instrument, asset, useAsCollateral , _instruments, _usersConfig[msg.sender],_instrumentsList, _instrumentsCount, addressesProvider.getPriceOracle() );
        _usersConfig[msg.sender].setUsingAsCollateral(instrument.id, useAsCollateral);

        if (useAsCollateral) {
            emit InstrumentUsedAsCollateralEnabled(asset, msg.sender);
        }
        else {
            emit InstrumentUsedAsCollateralDisabled(asset, msg.sender);
        }
    }

  /**
   * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
   * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
   *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param user The address of the borrower getting liquidated
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param _receiveIToken `true` if the liquidators wants to receive the collateral iTokens, `false` if he wants to receive the underlying collateral asset directly
   **/
    function liquidationCall( address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool _receiveIToken ) external override whenNotPaused {
        address collateralManager = addressesProvider.getLendingPoolLiquidationManager();

        (bool success, bytes memory result) =  collateralManager.delegatecall( abi.encodeWithSignature('liquidationCall(address,address,address,uint256,bool)', collateralAsset, debtAsset, user, debtToCover, _receiveIToken ) );
        require(success, "Liquidation Call failed");

        (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

        require(returnCode == 0, string(abi.encodePacked(returnMessage)));
  }


  struct FlashLoanLocalVars {
    IFlashLoanReceiver receiver;
    address oracle;
    uint256 i;
    address currentAsset;
    address currentITokenAddress;
    uint256 currentAmount;
    uint256 currentPremium;
    uint256 currentAmountPlusPremium;
    address debtToken;
  }

  /**
   * @dev Allows smartcontracts to access the liquidity of the pool within one transaction, as long as the amount taken plus a fee is returned.
   * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
   * For further details please visit https://developers.aave.com
   * @param receiverAddress The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface
   * @param assets The addresses of the assets being flash-borrowed
   * @param amounts The amounts amounts being flash-borrowed
   * @param modes Types of the debt to open if the flash loan is not returned:
   *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
   *   1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
   *   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
   * @param onBehalfOf The address  that will receive the debt in the case of using on `modes` 1 or 2
   * @param params Variadic packed params to pass to the receiver as extra information
   * @param boosterId Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   **/
  function flashLoan( address receiverAddress, address[] calldata assets, uint256[] calldata amounts, uint256[] calldata modes, address onBehalfOf, bytes calldata params, uint16 boosterId) external override whenNotPaused {
    FlashLoanLocalVars memory vars;

    ValidationLogic.validateFlashloan(assets, amounts);

    address[] memory iTokenAddresses = new address[](assets.length);
    uint256[] memory premiums = new uint256[](assets.length);

    vars.receiver = IFlashLoanReceiver(receiverAddress);

    for (vars.i = 0; vars.i < assets.length; vars.i++) {
        iTokenAddresses[vars.i] =_instruments[assets[vars.i]].iTokenAddress;
        premiums[vars.i] = feeProvider.calculateFlashLoanFee(msg.sender, amounts[vars.i], boosterId);
        IIToken(iTokenAddresses[vars.i]).transferUnderlyingTo(receiverAddress, amounts[vars.i]);
    }

    require( vars.receiver.executeOperation(assets, amounts, premiums, msg.sender, params), "ExecuteOperation() invalid return");

    for (vars.i = 0; vars.i < assets.length; vars.i++) {
        vars.currentAsset = assets[vars.i];
        vars.currentAmount = amounts[vars.i];
        vars.currentPremium = premiums[vars.i];
        vars.currentITokenAddress = iTokenAddresses[vars.i];
        vars.currentAmountPlusPremium = vars.currentAmount.add(vars.currentPremium);

      if (DataTypes.InterestRateMode(modes[vars.i]) == DataTypes.InterestRateMode.NONE) {
       _instruments[vars.currentAsset].updateState(sighPayAggregator);
       _instruments[vars.currentAsset].cumulateToLiquidityIndex( IERC20(vars.currentITokenAddress).totalSupply(), vars.currentPremium );
       _instruments[vars.currentAsset].updateInterestRates(  vars.currentAsset, vars.currentITokenAddress, vars.currentAmountPlusPremium, 0 );
        sighVolatilityHarvester.updateSIGHBorrowIndex(vars.currentAsset);                    // Update SIGH Borrow Index for Instrument

        IERC20(vars.currentAsset).safeTransferFrom( receiverAddress, vars.currentITokenAddress, vars.currentAmountPlusPremium);
      }
      else {
        // If the user chose to not return the funds, the system checks if there is enough collateral and eventually opens a debt position
        _executeBorrow( ExecuteBorrowParams( vars.currentAsset, msg.sender, onBehalfOf, vars.currentAmount, modes[vars.i], vars.currentITokenAddress,0,0, boosterId, false ) );
      }
      emit FlashLoan(  receiverAddress, msg.sender, vars.currentAsset, vars.currentAmount, vars.currentPremium, boosterId );
    }
  }


// ###################################################################
// ######  VIEW FUNCTIONS TO FETCH DATA FROM THE CONTRACT  ###########
// ######  1. getInstrumentConfigurationData()  ######################
// ######  2. getInstrumentData()  ###################################
// ######  3. getUserAccountData()  ##################################
// ######  4. getUserConfiguration()  ################################
// ######  5. getUserInstrumentData()  ###############################
// ######    getInstrumentNormalizedIncome()   #######################
// ######  getInstrumentNormalizedVariableDebt()   ###################
// ######  paused()   ################################################
// ######  getInstrumentsList()   ####################################
// ######  getAddressesProvider()   ##################################
// ###################################################################


    // Returns the state and configuration of the instrument reserve
    function getInstrumentData(address asset) external view override returns (DataTypes.InstrumentData memory) {
        return _instruments[asset];
    }

    // Returns the user account data across all the instrument reserves
    function getUserAccountData(address user) external view override returns ( uint256 totalCollateralUSD, uint256 totalDebtUSD, uint256 availableBorrowsUSD, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor ) {
        ( totalCollateralUSD, totalDebtUSD, ltv, currentLiquidationThreshold, healthFactor ) = GenericLogic.calculateUserAccountData( user,_instruments, _usersConfig[user],_instrumentsList,_instrumentsCount, addressesProvider.getPriceOracle() );
        availableBorrowsUSD = GenericLogic.calculateAvailableBorrowsUSD( totalCollateralUSD, totalDebtUSD, ltv );
    }

    function getInstrumentConfiguration(address asset) external override view returns ( DataTypes.InstrumentConfigurationMap memory ) {
        return _instruments[asset].configuration;
    }

    // Returns the configuration of the user across all the instrument reserves
    function getUserConfiguration(address user) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

   // Returns the normalized income per unit of asset
    function getInstrumentNormalizedIncome(address asset) external view virtual override returns (uint256) {
        return _instruments[asset].getNormalizedIncome();
    }


   // Returns the normalized variable debt per unit of asset
    function getInstrumentNormalizedVariableDebt(address asset) external view override returns (uint256) {
        return _instruments[asset].getNormalizedDebt();
    }

    // Returns the list of the initialized reserves
    function getInstrumentsList() external view override returns (address[] memory) {
        address[] memory _activeInstruments = new address[](_instrumentsCount);

        for (uint256 i = 0; i <_instrumentsCount; i++) {
            _activeInstruments[i] =_instrumentsList[i];
        }
        return _activeInstruments;
    }


// ####################################################################
// ######  FUNCTION TO VALIDATE AN IITOKEN TRANSFER  ##################
// ######  1. finalizeTransfer()  #####################################
// ####################################################################

    /**
    * @dev Validates and finalizes an iToken transfer. Only callable by the overlying iToken of the `asset`
    * @param asset The address of the underlying asset of the iToken
    * @param from The user from which the iTokens are transferred
    * @param to The user receiving the iTokens
    * @param amount The amount being transferred/withdrawn
    * @param balanceFromBefore The iToken balance of the `from` user before the transfer
    * @param balanceToBefore The iToken balance of the `to` user before the transfer
    */
    function finalizeTransfer( address asset, address from,  address to, uint256 amount,  uint256 balanceFromBefore, uint256 balanceToBefore ) external override whenNotPaused {
        require(msg.sender ==_instruments[asset].iTokenAddress, "Only the associated IToken can call this function");

        ValidationLogic.validateTransfer( from, _instruments, _usersConfig[from], _instrumentsList, _instrumentsCount, addressesProvider.getPriceOracle() );
        sighVolatilityHarvester.updateSIGHSupplyIndex(asset);                    // Update SIGH Supply Index for Instrument

        uint256 instrumentId =_instruments[asset].id;

        if (from != to) {
            if (balanceFromBefore.sub(amount) == 0) {
                DataTypes.UserConfigurationMap storage fromConfig = _usersConfig[from];
                fromConfig.setUsingAsCollateral(instrumentId, false);
                emit InstrumentUsedAsCollateralDisabled(asset, from);
            }
            if (balanceToBefore == 0 && amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = _usersConfig[to];
                toConfig.setUsingAsCollateral(instrumentId, true);
                emit InstrumentUsedAsCollateralEnabled(asset, to);
            }
        }
    }




// ############################################################################
// ####### ADMIN FUNCTIONS (Callable only by LendingPoolConfigurator)  ########
// ############################################################################


    /**
    * @dev Initializes a reserve, activating it, assigning an iToken and debt tokens and an interest rate strategy
    * - Only callable by the LendingPoolConfigurator contract
    * @param asset The address of the underlying asset of the reserve
    * @param iTokenAddress The address of the iToken that will be assigned to the reserve
    * @param stableDebtAddress The address of the StableDebtToken that will be assigned to the reserve
    * @param iTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
    * @param _SIGHHarvesterProxyAddress The address of the SIGH Streaming Contract
    * @param interestRateStrategyAddress The address of the interest rate strategy contract
    **/
    function initInstrument(address asset,address iTokenAddress, address stableDebtAddress, address variableDebtAddress, address _SIGHHarvesterProxyAddress, address interestRateStrategyAddress, uint8 underlyingAssetDecimals) external override onlyLendingPoolConfigurator {
        require(Address.isContract(asset), "Instrument address is not a contract");
        _instruments[asset].init( iTokenAddress, stableDebtAddress, variableDebtAddress, interestRateStrategyAddress );
        _addInstrumentToList(asset);

        require( sighVolatilityHarvester.addInstrument( asset, iTokenAddress,stableDebtAddress, variableDebtAddress, _SIGHHarvesterProxyAddress, underlyingAssetDecimals ), "Instrument failed to be properly added to the list of Instruments supported by SIGH Finance" ); // ADDED BY SIGH FINANCE
        require( ISIGHHarvestDebtToken(iTokenAddress).setSIGHHarvesterAddress( _SIGHHarvesterProxyAddress ), "Sigh Harvester Address failed to be properly initialized on IIToken" );
        require( ISIGHHarvestDebtToken(variableDebtAddress).setSIGHHarvesterAddress( _SIGHHarvesterProxyAddress ), "Sigh Harvester Address failed to be properly initialized on Variable Debt Token");
        require( ISIGHHarvestDebtToken(stableDebtAddress).setSIGHHarvesterAddress( _SIGHHarvesterProxyAddress ), "Sigh Harvester Address failed to be properly initialized  on Stable Debt Token " );
    }

    /**
    * @dev Updates the address of the interest rate strategy contract. Only callable by the LendingPoolConfigurator contract
    * @param asset The address of the underlying asset of the reserve
    * @param rateStrategyAddress The address of the interest rate strategy contract
    **/
    function setInstrumentInterestRateStrategyAddress(address asset, address rateStrategyAddress) external override onlyLendingPoolConfigurator {
       _instruments[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
    * @dev Sets the configuration bitmap of the instrument as a whole. Only callable by the LendingPoolConfigurator contract
    * @param asset The address of the underlying asset of the instrument
    * @param configuration The new configuration bitmap
    **/
    function setConfiguration(address asset, uint256 configuration) external override onlyLendingPoolConfigurator {
       _instruments[asset].configuration.data = configuration;
    }

    /**
    * @dev Set the _pause state of a instrument. Only callable by the LendingPoolConfigurator contract
    * @param val `true` to pause the instrument, `false` to un-pause it
    */
    function setPause(bool val) external override onlyLendingPoolConfigurator {
        _paused = val;
        if (_paused) {
            emit Paused();
        }
        else {
            emit Unpaused();
        }
    }






// ####################################
// ####### INTERNAL FUNCTIONS  ########
// ####################################

  struct ExecuteBorrowParams {
    address asset;
    address user;
    address onBehalfOf;
    uint256 amount;
    uint256 interestRateMode;
    address iTokenAddress;
    uint16 boosterId;
    uint256 platformFee;
    uint256 reserveFee;
    bool releaseUnderlying;
  }

    function _executeBorrow(ExecuteBorrowParams memory vars) internal {
        DataTypes.InstrumentData storage instrument =_instruments[vars.asset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.onBehalfOf];

        address oracle = addressesProvider.getPriceOracle();
        uint256 amountInUSD = IPriceOracleGetter(oracle).getAssetPrice(vars.asset).mul(vars.amount).div(  10**instrument.configuration.getDecimals() );

        ValidationLogic.validateBorrow( vars.asset, instrument, vars.onBehalfOf, vars.amount, amountInUSD, vars.interestRateMode, MAX_STABLE_RATE_BORROW_SIZE_PERCENT,_instruments, userConfig,_instrumentsList,_instrumentsCount, oracle );
        instrument.updateState(sighPayAggregator);

        uint256 currentStableRate = 0;
        bool isFirstBorrowing = false;
        
        // Fee Related
        (vars.platformFee, vars.reserveFee) = feeProvider.calculateBorrowFee(vars.onBehalfOf , vars.asset, vars.amount, vars.boosterId);
        ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).updatePlatformFee(vars.user,vars.platformFee,0);
        ISIGHHarvestDebtToken(instrument.stableDebtTokenAddress).updateReserveFee(vars.user,vars.reserveFee,0);

        if (DataTypes.InterestRateMode(vars.interestRateMode) == DataTypes.InterestRateMode.STABLE) {
            currentStableRate = instrument.currentStableBorrowRate;
            isFirstBorrowing = IStableDebtToken(instrument.stableDebtTokenAddress).mint( vars.user, vars.onBehalfOf, vars.amount, currentStableRate );
        }
        else {
            isFirstBorrowing = IVariableDebtToken(instrument.variableDebtTokenAddress).mint( vars.user, vars.onBehalfOf, vars.amount, instrument.variableBorrowIndex );
        }
        
        
        if (isFirstBorrowing) {
            userConfig.setBorrowing(instrument.id, true);
        }

        instrument.updateInterestRates( vars.asset, vars.iTokenAddress, 0, vars.releaseUnderlying ? vars.amount : 0 );

        if (vars.releaseUnderlying) {
            IIToken(vars.iTokenAddress).transferUnderlyingTo(vars.user, vars.amount);
        }

        emit Borrow( vars.asset, vars.user, vars.onBehalfOf, vars.amount, vars.platformFee, vars.reserveFee, vars.interestRateMode, DataTypes.InterestRateMode(vars.interestRateMode) == DataTypes.InterestRateMode.STABLE ? currentStableRate : instrument.currentVariableBorrowRate, vars.boosterId );
    }



    function _addInstrumentToList(address asset) internal {
        uint256 instrumentsCount =_instrumentsCount;
        require(instrumentsCount < _MAX_NUMBER_INSTRUMENTS, " NO MORE INSTRUMENTS ALLOWED");
        bool instrumentAlreadyAdded =_instruments[asset].id != 0 ||_instrumentsList[0] == asset;

        if (!instrumentAlreadyAdded) {
           _instruments[asset].id = uint8(instrumentsCount);
           _instrumentsList[instrumentsCount] = asset;
           _instrumentsCount = instrumentsCount + 1;
        }
    }

}