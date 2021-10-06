// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategyMultiToken,
    StrategyParams
} from "./BaseStrategyMultiToken.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./IUniswapV2Router.sol";
import "./IUniswapV2Pair.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategyMultiToken {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    IUniswapV2Pair pair =
        IUniswapV2Pair(0x3041CbD36888bECc7bbCBc0045E3B1f144466f5f);
    IUniswapV2Router router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint256[NUM_TOKENS] decimals;
    uint256[NUM_TOKENS] pendingProfits;
    uint256 constant PRECISION = 10**18;

    constructor(address[NUM_TOKENS] memory _vaults)
        public
        BaseStrategyMultiToken(_vaults)
    {
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            decimals[i] = vaults[i].decimals();
            SafeERC20.safeApprove(wants[i], address(router), uint256(-1));
        }
        SafeERC20.safeApprove(
            IERC20(address(pair)),
            address(router),
            uint256(-1)
        );
    }

    function name() external view override returns (string memory) {
        return "StrategyUniswapStablePairs";
    }

    function bumpAllowance() external {
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            SafeERC20.safeApprove(wants[i], address(router), uint256(-1));
        }
        SafeERC20.safeApprove(
            IERC20(address(pair)),
            address(router),
            uint256(-1)
        );
    }

    function estimatedTotalAssets(IERC20 _want)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalAssets = _want.balanceOf(address(this));

        uint256 balance = IERC20(_want).balanceOf(address(pair));
        uint256 liquidity = pair.balanceOf(address(this));
        totalAssets += liquidity.mul(balance) / pair.totalSupply();

        return totalAssets;
    }

    function prepareReturn(uint256 id, uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 loss = 0;
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, loss) = liquidatePosition(
                wants[id],
                _debtOutstanding
            );
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        uint256[NUM_TOKENS] memory balancesBefore;
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            balancesBefore[i] = wants[i].balanceOf(address(this));
        }

        if (_claimProfits(id)) {
            for (uint256 i = 0; i < NUM_TOKENS; i++) {
                pendingProfits[i] = wants[i]
                    .balanceOf(address(this))
                    .sub(balancesBefore[i])
                    .add(pendingProfits[i]);
            }
        }

        uint256 totalAssets = wants[id].balanceOf(address(this));
        uint256 totalDebt = vaults[id].strategies(address(this)).totalDebt;
        uint256 balance = IERC20(wants[id]).balanceOf(address(pair));
        uint256 liquidity = pair.balanceOf(address(this));
        totalAssets += liquidity.mul(balance).div(pair.totalSupply());

        if (totalAssets > _debtOutstanding) {
            _debtPayment = _debtOutstanding;
            totalAssets = totalAssets.sub(_debtOutstanding);
        } else {
            _debtPayment = totalAssets;
            totalAssets = 0;
        }
        totalDebt = totalDebt.sub(_debtPayment);

        if (totalAssets > totalDebt) {
            _profit = pendingProfits[id];
            pendingProfits[id] = 0;
        } else {
            _loss = totalDebt.sub(totalAssets) + loss;
        }
    }

    function _claimProfits(uint256 id) internal returns (bool) {
        uint256 totalAssets = wants[id].balanceOf(address(this));
        uint256 totalDebt = vaults[id].strategies(address(this)).totalDebt;
        uint256 balance = IERC20(wants[id]).balanceOf(address(pair));
        uint256 liquidity = pair.balanceOf(address(this));
        totalAssets += liquidity.mul(balance).div(pair.totalSupply());

        if (totalAssets <= totalDebt) {
            return false;
        }

        uint256 profitInWant = totalAssets.sub(totalDebt);

        liquidatePosition(wants[id], profitInWant);
        return true;
    }

    function adjustPositions(uint256[NUM_TOKENS] memory _debtOutstanding)
        internal
        override
    {
        uint256[NUM_TOKENS] memory balances;
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            balances[i] = wants[i].balanceOf(address(this));
        }

        uint256 min =
            Math.min(
                balances[0] / 10**decimals[0],
                balances[1] / 10**decimals[1]
            );
        if (min < 500) {
            // do not invest if not at least 500 usd on one side
            return;
        }

        router.addLiquidity(
            address(wants[0]),
            address(wants[1]),
            balances[0],
            balances[1],
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    function liquidatePosition(IERC20 _want, uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 initalAssetsBalance = _want.balanceOf(address(this));
        if (_amountNeeded > initalAssetsBalance) {
            uint256 missing = _amountNeeded.sub(initalAssetsBalance);

            uint256 totalLP = pair.balanceOf(address(this));
            if (totalLP > 0) {
                uint256 balance = IERC20(_want).balanceOf(address(pair));
                uint256 lpToBurn =
                    (missing * PRECISION) /
                        ((balance * PRECISION) / pair.totalSupply());

                if (lpToBurn > totalLP) {
                    lpToBurn = totalLP;
                }

                router.removeLiquidity(
                    address(wants[0]),
                    address(wants[1]),
                    lpToBurn,
                    1,
                    1,
                    address(this),
                    block.timestamp
                );
            }
        }
        uint256 totalAssets = _want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions(IERC20 _want)
        internal
        override
        returns (uint256)
    {
        uint256 totalLP = pair.balanceOf(address(this));
        if (totalLP != 0) {
            router.removeLiquidity(
                address(wants[0]),
                address(wants[1]),
                totalLP,
                1,
                1,
                address(this),
                block.timestamp
            );
        }

        return _want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWants(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256[NUM_TOKENS] memory)
    {
        // TODO create an accurate price oracle
        return [_amtInWei, _amtInWei];
    }
}
