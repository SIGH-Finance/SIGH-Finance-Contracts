from brownie import *

def main():
    boosters = SIGHBoosters.deploy('SIGH Boosters','BST',{'from':accounts[0]})