// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {DataTypes} from '../types/DataTypes.sol';
import "../../../dependencies/openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title Helpers library
 * @author Aave
 */
library Helpers {

  /**
   * @dev Fetches the user current stable and variable debt balances
   * @param user The user address
   * @param instrument The instrument data object
   * @return The stable and variable debt balance
   **/
  function getUserCurrentDebt(address user, DataTypes.InstrumentData storage instrument) internal view returns (uint256, uint256) {
    return ( IERC20(instrument.stableDebtTokenAddress).balanceOf(user), IERC20(instrument.variableDebtTokenAddress).balanceOf(user) );
  }

  function getUserCurrentDebtMemory(address user, DataTypes.InstrumentData memory instrument) internal view returns (uint256, uint256) {
    return ( IERC20(instrument.stableDebtTokenAddress).balanceOf(user), IERC20(instrument.variableDebtTokenAddress).balanceOf(user) );
  }

  /**
   * @dev Fetches the user current Platform Fee for both stable and variable debt balances
   * @param user The user address
   * @param instrument The instrument data object
   * @return The stable and variable debt platform fee
   **/
  function getUserCurrentPlatformFee(address user, DataTypes.InstrumentData storage instrument) internal view returns (uint256, uint256) {
    return ( IERC20(instrument.stableDebtTokenAddress).getPlatformFee(user), IERC20(instrument.variableDebtTokenAddress).getPlatformFee(user) );
  }

  /**
   * @dev Fetches the user current Reserve Fee for both stable and variable debt balances
   * @param user The user address
   * @param instrument The instrument data object
   * @return The stable and variable debt reserve fee
   **/
  function getUserReserveFee(address user, DataTypes.InstrumentData storage instrument) internal view returns (uint256, uint256) {
    return ( IERC20(instrument.stableDebtTokenAddress).getReserveFee(user), IERC20(instrument.variableDebtTokenAddress).getReserveFee(user) );
  }

}