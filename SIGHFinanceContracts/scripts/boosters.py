from brownie import *


def main():
    boosters = SIGHBoosters.deploy('SIGH Boosters', 'BST', {'from': accounts[0]})

    # Update Boosters baseURI
    boosters._updateBaseURI('boosters.sigh.finance',{'from':accounts[0]})

    # Add Booster Types (Inspired from Hitchhicker's to the Galaxy)
    boosters.addNewBoosterType('Deep Thought', 100, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('JARVIS', 50, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('MARVIN', 25, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('Tangerine star buggy', 10, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('Heart of Gold', 10, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('The Restaurant at the End of the Universe', 5, 5, {'from': accounts[0]})
