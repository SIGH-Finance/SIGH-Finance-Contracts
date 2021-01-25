import pytest
import brownie
from brownie import SIGHBoosters, accounts


@pytest.fixture
def boosters():
    return SIGHBoosters.deploy('SIGH Boosters', 'SB', {'from': accounts[0]})


def test_deploy(boosters):
    assert boosters.name() == 'SIGH Boosters'
    assert boosters.symbol() == 'SB'
    assert boosters.owner() == accounts[0]


def test_supportsInterface(boosters):
    assert boosters.supportsInterface('0x01ffc9a7') == True  # _INTERFACE_ID_ERC165
    assert boosters.supportsInterface('0x80ac58cd') == True  # _INTERFACE_ID_ERC721
    assert boosters.supportsInterface('0x5b5e139f') == True  # _INTERFACE_ID_ERC721_METADATA
    assert boosters.supportsInterface('0x780e9d63') == True  # _INTERFACE_ID_ERC721_ENUMERABLE
    assert boosters.supportsInterface('0xffffffff') == False  # invalid interface id
    assert boosters.supportsInterface('0x150b7a02') == False  # _ERC721_RECEIVED


def test_addNewBoosterType(boosters):
    boosters.addNewBoosterType('Marvin', 100, 5, {'from': accounts[0]})
    assert boosters.isCategorySupported('Marvin') == True
    assert boosters.totalBoostersAvailable('Marvin') == 0
    assert boosters.getAllBoosterTypes() == ['Marvin']
    assert boosters.getDiscountRatiosForBoosterCategory('Marvin') == (100, 5)


def test_updateBaseURI(boosters):
    boosters._updateBaseURI('boosters/sigh.finance', {'from': accounts[0]})
    assert boosters.baseURI() == 'boosters/sigh.finance'
    with brownie.reverts():
        boosters._updateBaseURI('boosters/sigh.finance', {'from': accounts[2]})
