import pytest
import brownie
from brownie import SIGHBoostersSale,SIGHBoosters, accounts


@pytest.fixture
def boostersSale():
    boosters = SIGHBoosters.deploy('SIGH Boosters', 'SB', {'from': accounts[0]})
    #Add new booster type
    boosters.addNewBoosterType('Deep Thought', 100, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('Heart of Gold', 10, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('The Restaurant at the End of the Universe', 5, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('MARVIN', 100, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('JARVIS', 50, 5, {'from': accounts[0]})
    #Create new boosters
    boosters.createNewBoosters(['Deep Thought','Heart of Gold','The Restaurant at the End of the Universe'],
                               ['dt/1','hg/1','r/1'], {'from': accounts[0]}) # 1 each
    boosters.createNewBoosters(['JARVIS','JARVIS','JARVIS','JARVIS','JARVIS','JARVIS','JARVIS','JARVIS','JARVIS','JARVIS'],
                               ['jrvs/1','jrvs/2','jrvs/3','jrvs/4','jrvs/5','jrvs/6','jrvs/7','jrvs/8','jrvs/9','jrvs/10'],
                               {'from': accounts[0]}) #10
    boosters.createNewBoosters(['MARVIN','MARVIN','MARVIN','MARVIN','MARVIN','MARVIN','MARVIN','MARVIN','MARVIN','MARVIN'],
                               ['mrvn/1','mrvn/2','mrvn/3','mrvn/4','mrvn/5','mrvn/6','mrvn/7','mrvn/8','mrvn/9','mrvn/10'],
                               {'from': accounts[0]}) #10
    #update base URI
    boosters._updateBaseURI('boosters/sigh.finance/', {'from': accounts[0]})

    boostersSale = SIGHBoostersSale.deploy(boosters.address, {'from': accounts[0]})
    return boosters, boostersSale