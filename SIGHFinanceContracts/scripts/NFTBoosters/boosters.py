from brownie import *


def main():
    boosters = SIGHBoosters.deploy('SIGH Boosters', 'BST', {'from': accounts[0]})

    # Update Boosters baseURI
    boosters._updateBaseURI('boosters.sigh.finance/',{'from':accounts[0]})

    # Add Booster Types (Inspired from Hitchhicker's to the Galaxy)
    boosters.addNewBoosterType('Deep Thought', 100, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('Heart of Gold', 10, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('The Restaurant at the End of the Universe', 5, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('Tangerine star buggy', 10, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('JARVIS', 50, 5, {'from': accounts[0]})
    boosters.addNewBoosterType('MARVIN', 25, 5, {'from': accounts[0]})

    #Add Boosters
    boosters.createNewBoosters(['Deep Thought','Heart of Gold','The Restaurant at the End of the Universe'],
                               ['dt/1','hg/1','r/1'], {'from': accounts[0]})
    boosters.createNewBoosters(['Tangerine star buggy','Tangerine star buggy',
                                'Tangerine star buggy','Tangerine star buggy'],
                               ['tsb/1','tsb/2','tsb/3','tsb/4'], {'from': accounts[0]})
    boosters.createNewBoosters(['JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS'],
                               ['jrvs/1','jrvs/2','jrvs/3','jrvs/4','jrvs/5',
                                'jrvs/6','jrvs/7','jrvs/8','jrvs/9','jrvs/10',
                                'jrvs/11','jrvs/12','jrvs/13','jrvs/14','jrvs/15',
                                'jrvs/16','jrvs/17','jrvs/18','jrvs/19','jrvs/20',
                                'jrvs/21','jrvs/22','jrvs/23','jrvs/24','jrvs/25',
                                'jrvs/26','jrvs/27','jrvs/28','jrvs/29','jrvs/30',
                                'jrvs/31','jrvs/32','jrvs/33','jrvs/34','jrvs/35',
                                'jrvs/36','jrvs/37','jrvs/38','jrvs/39','jrvs/40',
                                'jrvs/41','jrvs/42','jrvs/43','jrvs/44','jrvs/45',
                                'jrvs/46','jrvs/47','jrvs/48','jrvs/49','jrvs/50'],
                               {'from': accounts[0]})
    boosters.createNewBoosters(['JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS',
                                'JARVIS','JARVIS','JARVIS','JARVIS','JARVIS'],
                               ['jrvs/51','jrvs/52','jrvs/53','jrvs/54','jrvs/55',
                                'jrvs/56','jrvs/57','jrvs/58','jrvs/59','jrvs/60',
                                'jrvs/61','jrvs/62','jrvs/63','jrvs/64','jrvs/65',
                                'jrvs/66','jrvs/67','jrvs/18','jrvs/19','jrvs/20',
                                'jrvs/21','jrvs/22','jrvs/23','jrvs/24','jrvs/25',
                                'jrvs/26','jrvs/27','jrvs/28','jrvs/29','jrvs/30',
                                'jrvs/31','jrvs/32','jrvs/33','jrvs/34','jrvs/35',
                                'jrvs/36','jrvs/37','jrvs/38','jrvs/39','jrvs/40',
                                'jrvs/41','jrvs/42','jrvs/43','jrvs/44','jrvs/45',
                                'jrvs/46','jrvs/47','jrvs/48','jrvs/49','jrvs/50'],
                               {'from': accounts[0]})
    boosters.createNewBoosters(['MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN',
                                'MARVIN','MARVIN','MARVIN','MARVIN','MARVIN'],
                               ['mrvn/1','mrvn/2','mrvn/3','mrvn/4','mrvn/5',
                                'mrvn/6','mrvn/7','mrvn/8','mrvn/9','mrvn/10',
                                'mrvn/11','mrvn/12','mrvn/13','mrvn/14','mrvn/15',
                                'mrvn/16','mrvn/17','mrvn/18','mrvn/19','mrvn/20',
                                'mrvn/21','mrvn/22','mrvn/23','mrvn/24','mrvn/25',
                                'mrvn/26','mrvn/27','mrvn/28','mrvn/29','mrvn/30',
                                'mrvn/31','mrvn/32','mrvn/33','mrvn/34','mrvn/35',
                                'mrvn/36','mrvn/37','mrvn/38','mrvn/39','mrvn/40',
                                'mrvn/41','mrvn/42','mrvn/43','mrvn/44','mrvn/45',
                                'mrvn/46','mrvn/47','mrvn/48','mrvn/49','mrvn/50'],
                               {'from': accounts[0]})
    return boosters

