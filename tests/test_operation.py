import brownie
from brownie import Contract
import pytest


def test_operation(
    chain, accounts, tokens, vaults, strategy, user, strategist, amounts, RELATIVE_APPROX
):
    # Deposit to the vault
    user_balance_before0 = tokens[0].balanceOf(user)
    tokens[0].approve(vaults[0].address, amounts[0], {"from": user})
    vaults[0].deposit(amounts[0], {"from": user})
    assert tokens[0].balanceOf(vaults[0].address) == amounts[0]

    user_balance_before1 = tokens[1].balanceOf(user)
    tokens[1].approve(vaults[1].address, amounts[1], {"from": user})
    vaults[1].deposit(amounts[1], {"from": user})
    assert tokens[1].balanceOf(vaults[1].address) == amounts[1]

    # harvest
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(tokens[0]), rel=RELATIVE_APPROX) == amounts[0]
    assert pytest.approx(strategy.estimatedTotalAssets(tokens[1]), rel=RELATIVE_APPROX) == amounts[1]

    # tend()
    strategy.tend()

    # withdrawal
    vaults[0].withdraw({"from": user})
    assert (
        pytest.approx(tokens[0].balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before0
    )
    vaults[1].withdraw({"from": user})
    assert (
        pytest.approx(tokens[1].balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before1
    )


# def test_emergency_exit(
#     chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX
# ):
#     # Deposit to the vault
#     token.approve(vault.address, amount, {"from": user})
#     vault.deposit(amount, {"from": user})
#     chain.sleep(1)
#     strategy.harvest()
#     assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

#     # set emergency and exit
#     strategy.setEmergencyExit()
#     chain.sleep(1)
#     strategy.harvest()
#     assert strategy.estimatedTotalAssets() < amount


def test_profitable_harvest(
    chain, gov, tokens, vaults, strategy, user, strategist, amounts, RELATIVE_APPROX
):
    # Deposit to the vault
    tokens[0].approve(vaults[0].address, amounts[0], {"from": user})
    vaults[0].deposit(amounts[0], {"from": user})
    assert tokens[0].balanceOf(vaults[0].address) == amounts[0]

    tokens[1].approve(vaults[1].address, amounts[1], {"from": user})
    vaults[1].deposit(amounts[1], {"from": user})
    assert tokens[1].balanceOf(vaults[1].address) == amounts[1]

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(tokens[0]), rel=RELATIVE_APPROX) == amounts[0]
    assert pytest.approx(strategy.estimatedTotalAssets(tokens[1]), rel=RELATIVE_APPROX) == amounts[1]

    # TODO: Add some code before harvest #2 to simulate earning yield
    
    tokens[0].transfer(strategy, amounts[0] / 1_000, {"from": gov})
    tokens[1].transfer(strategy, amounts[1] / 1_000, {"from": gov})

    # Harvest 2: Realize profit
    chain.sleep(1)
    strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit0 = tokens[0].balanceOf(vaults[0].address)  # Profits go to vault
    profit1 = tokens[1].balanceOf(vaults[1].address)  # Profits go to vault
    assert profit0 == amounts[0] / 1_000
    assert profit1 == amounts[1] / 1_000
    # TODO: Uncomment the lines below
    # assert token.balanceOf(strategy) + profit > amount
    # assert vault.pricePerShare() > before_pps


# def test_change_debt(
#     chain, gov, tokens, vaults, strategy, user, strategist, amount, RELATIVE_APPROX
# ):
#     # Deposit to the vault and harvest
#     tokens[0].approve(vault.address, amount, {"from": user})
#     vaults[0].deposit(amount, {"from": user})
#     vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
#     chain.sleep(1)
#     strategy.harvest()
#     half = int(amount / 2)

#     assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half

#     vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
#     chain.sleep(1)
#     strategy.harvest()
#     assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

#     # In order to pass this tests, you will need to implement prepareReturn.
#     # TODO: uncomment the following lines.
#     # vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
#     # chain.sleep(1)
#     # strategy.harvest()
#     # assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half

