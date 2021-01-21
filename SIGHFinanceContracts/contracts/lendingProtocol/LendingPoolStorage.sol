// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {UserConfiguration} from './libraries/configuration/UserConfiguration.sol';
import {InstrumentConfiguration} from './libraries/configuration/InstrumentConfiguration.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';

import {ReserveLogic} from '../libraries/logic/ReserveLogic.sol';


contract LendingPoolStorage {

  using ReserveLogic for DataTypes.ReserveData;
  using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  IGlobalAddressesProvider internal _addressesProvider;

  mapping(address => DataTypes.ReserveData) internal _instruments;
  mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

  mapping(uint256 => address) internal _instrumentsList;    // the list of the available instruments, structured as a mapping for gas savings reasons
  uint256 internal _instrumentsCount;

  bool internal _paused;
}