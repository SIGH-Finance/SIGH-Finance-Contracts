import os
from brownie import accounts,network,GlobalAddressesProvider,SIGH, SIGHSpeedController,SIGHVolatilityHarvester,SIGHFinanceConfigurator
from brownie import FeeProvider, LendingRateOracle, LendingPoolLiquidationManager, LendingPoolConfigurator, LendingPool
from brownie import MockProxyPriceProvider, ChainlinkProxyPriceProvider
from brownie import SIGH_PAY_Aggregator, SIGH_Fee_Collector

def main():
    return deploySIGHFinance()


def deploySIGHFinance():
    if network.show_active() == 'mainnet-fork' or  network.show_active()== 'development':
        return deployScript(accounts[0])
    elif network.show_active() == 'kovan':
        dev = accounts.add(os.getenv('PRIVATE_KEY'))
        return deployScript(dev)


def deployScript(account):
    globalAddressesProvider = GlobalAddressesProvider.deploy(account, account, {'from': account}) #SIGH Finance Manager, Lending Pool Manager

    # SIGH CONTRACTS
    SIGH_ = SIGH.deploy({'from':account})
    globalAddressesProvider.setSIGHAddress(SIGH_.address,{'from':account})

    SIGHspeedController_ = SIGHSpeedController.deploy({'from':a[0]})
    globalAddressesProvider.setSIGHSpeedController(SIGHspeedController_.address,{'from':account})

    SIGHVolatilityHarvester_ = SIGHVolatilityHarvester.deploy({'from':a[0]})
    globalAddressesProvider.setSIGHVolatilityHarvesterImpl(SIGHVolatilityHarvester_.address,{'from':account})

    SighFinanceConfigurator_ = SIGHFinanceConfigurator.deploy({'from':a[0]})
    globalAddressesProvider.setSIGHFinanceConfiguratorImpl(SighFinanceConfigurator_.address,{'from':account})

    # LENDING PROTOCOL CONTRACTS
    FeeProvider_ = FeeProvider.deploy({'from':a[0]})
    globalAddressesProvider.setFeeProviderImpl(FeeProvider_.address,{'from':account})

    LendingRateOracle_ = LendingRateOracle.deploy({'from': a[0]})
    globalAddressesProvider.setLendingRateOracle(LendingRateOracle_.address, {'from': account})

    LendingPoolLiquidationManager_ = LendingPoolLiquidationManager.deploy({'from': a[0]})
    globalAddressesProvider.setLendingPoolLiquidationManager(LendingPoolLiquidationManager_.address, {'from': account})

    LendingPoolConfigurator_ = LendingPoolConfigurator.deploy({'from': a[0]})
    globalAddressesProvider.setLendingPoolConfiguratorImpl(LendingPoolConfigurator_.address, {'from': account})

    LendingPool_ = LendingPool.deploy({'from': a[0]})
    globalAddressesProvider.setLendingPoolImpl(LendingPool_.address, {'from': account})

    #Price oracle
    priceOracle = []
    if network.show_active() == 'mainnet-fork' or  network.show_active() == 'development':
        priceOracle = MockProxyPriceProvider.deploy(globalAddressesProvider.address,{'from': account})
    elif network.show_active() == 'kovan':
        priceOracle = ChainlinkProxyPriceProvider.deploy(globalAddressesProvider.address,{'from': account})

    globalAddressesProvider.setPriceOracle(priceOracle.address,{'from': account})

    # SIGH PAY Aggregator & SIGH Fee Collector
    SIGH_PAY_Aggregator_ = SIGH_PAY_Aggregator.deploy({'from': account})
    globalAddressesProvider.setSIGHPAYAggregator(SIGH_PAY_Aggregator_.address,{'from': account})

    SIGH_Fee_Collector_ = SIGH_Fee_Collector.deploy(globalAddressesProvider.address,{'from': account})
    globalAddressesProvider.setSIGHFinanceFeeCollector(SIGH_Fee_Collector_.address,{'from': account})


def initializeSIGH(globalAddressesProvider,account):
    SIGH_ = globalAddressesProvider.getSIGHAddress()
    SIGHSpeedController_ = globalAddressesProvider.getSIGHSpeedController()
    SIGHVolatilityHarvester_ = globalAddressesProvider.getSIGHVolatilityHarvester()
    SIGHFinanceConfigurator_ = globalAddressesProvider.getSIGHFinanceConfigurator()

    # initialize SIGH Contracts
    SIGH(SIGH_).initMinting(globalAddressesProvider.address,SIGHSpeedController_,{'from': account})
    SIGHSpeedController(SIGHSpeedController_).beginDripping(SIGHVolatilityHarvester_,{'from': account})
    SIGHVolatilityHarvester(SIGHVolatilityHarvester_).refreshConfig({'from': account})


def initializeLendingProtocol(globalAddressesProvider,account):