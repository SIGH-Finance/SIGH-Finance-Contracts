from brownie import *


def main():
    boostersSale = SIGHBoostersSale.deploy('SIGH Boosters', 'BST', {'from': accounts[0]})
