import pytest
from brownie import config
from brownie import Contract


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def tokens():
    yield [
        Contract("0xdAC17F958D2ee523a2206206994597C13D831ec7"),
        Contract("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
    ]


@pytest.fixture
def amounts(get_tokens, user, gov):
    get_tokens(gov)
    yield get_tokens(user)


@pytest.fixture
def get_tokens(accounts, tokens):
    def get_tokens(to):
        amount0 = 10_000 * 10 ** tokens[0].decimals()
        reserve = accounts.at("0x5754284f345afc66a98fbb0a0afe71e0f007b949", force=True)
        tokens[0].transfer(to, amount0, {"from": reserve})

        amount1 = 10_000 * 10 ** tokens[1].decimals()
        reserve = accounts.at("0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503", force=True)
        tokens[1].transfer(to, amount1, {"from": reserve})
        return [amount0, amount1]

    yield get_tokens


@pytest.fixture
def vaults(pm, gov, rewards, guardian, management, tokens):
    Vault = pm(config["dependencies"][0]).Vault
    vault0 = guardian.deploy(Vault)
    vault0.initialize(tokens[0], gov, rewards, "", "", guardian, management)
    vault0.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault0.setManagement(management, {"from": gov})

    vault1 = guardian.deploy(Vault)
    vault1.initialize(tokens[1], gov, rewards, "", "", guardian, management)
    vault1.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault1.setManagement(management, {"from": gov})
    yield [vault0, vault1]


@pytest.fixture
def strategy(strategist, keeper, vaults, Strategy, gov):
    strategy = strategist.deploy(Strategy, vaults)
    strategy.setKeeper(keeper)
    vaults[0].addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    vaults[1].addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    yield strategy


@pytest.fixture
def uniswap_router():
    yield Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
