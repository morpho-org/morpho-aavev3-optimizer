// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {PermitHash} from "@permit2/libraries/PermitHash.sol";
import {IAllowanceTransfer, AllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";
import {Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BulkerGateway} from "src/extensions/BulkerGateway.sol";
import {IBulkerGateway} from "src/interfaces/IBulkerGateway.sol";

import {SigUtils} from "test/helpers/SigUtils.sol";

import "test/helpers/IntegrationTest.sol";

contract TestExtensionsBulker is IntegrationTest {
    using SafeTransferLib for ERC20;

    AllowanceTransfer internal constant PERMIT2 = AllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    SigUtils internal sigUtils;
    IBulkerGateway internal bulker;

    function setUp() public virtual override {
        super.setUp();
        bulker = new BulkerGateway(address(morpho));
        sigUtils = new SigUtils(morpho.DOMAIN_SEPARATOR());
    }

    function testShouldNotDeployWithMorphoZeroAddress() public {
        vm.expectRevert(IBulkerGateway.AddressIsZero.selector);
        new BulkerGateway(address(0));
    }

    function testShouldApproveAfterDeploy() public {
        assertEq(ERC20(bulker.WETH()).allowance(address(bulker), address(morpho)), type(uint256).max);
        assertEq(ERC20(bulker.stETH()).allowance(address(bulker), bulker.wstETH()), type(uint256).max);
        assertEq(ERC20(bulker.wstETH()).allowance(address(bulker), address(morpho)), type(uint256).max);
    }

    function testShouldApprove(uint256 seed, uint160 amount, uint256 privateKey) public {
        privateKey = bound(privateKey, 1, type(uint160).max);
        amount = uint160(bound(amount, 1, type(uint160).max));
        TestMarket memory market = testMarkets[_randomUnderlying(seed)];
        address delegator = vm.addr(privateKey);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);
        (actions[0], data[0]) =
            _getApproveData(privateKey, market.underlying, amount, type(uint48).max, IBulkerGateway.OpType.RAW);

        vm.prank(delegator);
        bulker.execute(actions, data);

        (uint160 allowance, uint48 newDeadline,) = PERMIT2.allowance(delegator, market.underlying, address(bulker));
        assertEq(allowance, amount, "allowance");
        assertEq(newDeadline, type(uint48).max, "deadline");
    }

    function testShouldTransferFrom(uint256 seed, uint256 amount, uint256 privateKey) public {
        privateKey = bound(privateKey, 1, type(uint160).max);
        amount = bound(amount, 1, type(uint160).max);
        TestMarket memory market = testMarkets[_randomUnderlying(seed)];
        address delegator = vm.addr(privateKey);
        deal(market.underlying, delegator, amount);

        vm.startPrank(delegator);
        ERC20(market.underlying).safeApprove(address(Permit2Lib.PERMIT2), 0);
        ERC20(market.underlying).safeApprove(address(Permit2Lib.PERMIT2), type(uint256).max);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](2);
        bytes[] memory data = new bytes[](2);
        (actions[0], data[0]) =
            _getApproveData(privateKey, market.underlying, uint160(amount), type(uint48).max, IBulkerGateway.OpType.RAW);
        (actions[1], data[1]) = _getTransferFromData(market.underlying, amount, IBulkerGateway.OpType.RAW);

        bulker.execute(actions, data);

        assertEq(ERC20(market.underlying).balanceOf(address(bulker)), amount, "bulker balance");
    }

    function testShouldWrapETH(address delegator, uint256 amount) public {
        amount = bound(amount, 1, type(uint160).max);
        deal(delegator, type(uint256).max);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getWrapETHData(amount, IBulkerGateway.OpType.RAW);

        vm.prank(delegator);
        bulker.execute{value: amount}(actions, data);
        assertEq(ERC20(bulker.WETH()).balanceOf(address(bulker)), amount, "bulker balance");
    }

    function testShouldUnwrapETH(address delegator, uint256 amount, address receiver) public {
        amount = bound(amount, 1, type(uint160).max);
        deal(wNative, amount);
        deal(wNative, address(bulker), amount);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getUnwrapETHData(amount, receiver, IBulkerGateway.OpType.RAW);

        uint256 balanceBefore = receiver.balance;

        vm.prank(delegator);
        bulker.execute(actions, data);

        assertEq(ERC20(bulker.WETH()).balanceOf(address(bulker)), 0, "bulker balance");
        assertEq(receiver.balance, balanceBefore + amount, "receiver balance");
    }

    // function testShouldWithdrawFromPool() public {
    //     for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
    //         if (snapshotId > 0) vm.revertTo(snapshotId);
    //         snapshotId = vm.snapshot();

    //         TestMarket memory market = markets[marketIndex];

    //         uint256 amount = ERC20(market.underlying).balanceOf(address(user));

    //         user.aaveSupply(market.underlying, amount);

    //         assertApproxEqAbs(
    //             ERC20(market.underlying).balanceOf(address(user)),
    //             0,
    //             1
    //         );

    //         IMainnetMorphoTxBuilder.ActionType[]
    //             memory actions = new IMainnetMorphoTxBuilder.ActionType[](1);
    //         bytes[] memory data = new bytes[](actions.length);

    //         (actions[0], data[0]) = user.encodeAaveWithdraw(
    //             market.underlying,
    //             amount - 1 // because of stEth rounding errors
    //         );

    //         user.execute(actions, data);

    //         assertApproxEqAbs(
    //             ERC20(market.underlying).balanceOf(address(user)),
    //             amount,
    //             1
    //         );
    //     }
    // }

    // function testShouldRepayToPool() public {
    //     uint256 wethBalanceBefore = ERC20(WETH).balanceOf(address(user));
    //     user.aaveSupply(WETH, wethBalanceBefore);
    //     (uint256 ltv, , , , ) = POOL.getConfiguration(WETH).getParamsMemory();

    //     for (
    //         uint256 marketIndex;
    //         marketIndex < borrowableMarkets.length;
    //         ++marketIndex
    //     ) {
    //         if (snapshotId > 0) vm.revertTo(snapshotId);
    //         snapshotId = vm.snapshot();

    //         TestMarket memory market = borrowableMarkets[marketIndex];

    //         uint256 borrowedBalanceBefore = ERC20(market.underlying).balanceOf(
    //             address(user)
    //         );
    //         uint256 borrowed = (
    //             market.underlying == WETH
    //                 ? wethBalanceBefore
    //                 : borrowedBalanceBefore
    //         ).percentMul(ltv);

    //         user.aaveBorrow(market.underlying, borrowed);

    //         assertEq(
    //             ERC20(market.underlying).balanceOf(address(user)),
    //             borrowedBalanceBefore + borrowed,
    //             "unexpected balance after borrow"
    //         );

    //         IMainnetMorphoTxBuilder.ActionType[]
    //             memory actions = new IMainnetMorphoTxBuilder.ActionType[](2);
    //         bytes[] memory data = new bytes[](actions.length);

    //         (actions[0], data[0]) = user.encodeApprove(
    //             market.underlying,
    //             address(POOL),
    //             borrowed
    //         );

    //         (actions[1], data[1]) = user.encodeAaveRepay(
    //             market.underlying,
    //             borrowed
    //         );

    //         user.execute(actions, data);

    //         assertApproxEqAbs(
    //             ERC20(market.underlying).balanceOf(address(user)),
    //             borrowedBalanceBefore,
    //             1,
    //             "unexpected balance after repay"
    //         );
    //     }
    // }

    //     function fold(TestMarket memory market)
    //     public
    //     returns (
    //         uint256 initialAmount,
    //         uint256 expectedSupply,
    //         uint256 expectedBorrow
    //     )
    // {
    //     initialAmount = ERC20(market.underlying).balanceOf(address(user));

    //     IMainnetMorphoTxBuilder.ActionType[]
    //         memory actions = new IMainnetMorphoTxBuilder.ActionType[](
    //             FOLDING_STEPS * 2 + 1
    //         );
    //     bytes[] memory data = new bytes[](actions.length);

    //     uint256 amount = initialAmount;
    //     for (uint256 i; i < FOLDING_STEPS; i++) {
    //         (actions[2 * i + 1], data[2 * i + 1]) = user.encodeSupply(
    //             market.poolToken,
    //             amount
    //         );
    //         expectedSupply += amount;

    //         amount = amount.percentMul(market.ltv).percentSub(1);
    //         (actions[2 * i + 2], data[2 * i + 2]) = user.encodeBorrow(
    //             market.poolToken,
    //             amount
    //         );
    //         expectedBorrow += amount;
    //     }

    //     (actions[0], data[0]) = user.encodeApprove(
    //         market.underlying,
    //         address(MORPHO),
    //         expectedSupply
    //     );

    //     user.execute(actions, data);
    // }

    // function testShouldFoldBorrowableCollateralMarket() public {
    //     for (
    //         uint256 marketIndex;
    //         marketIndex < borrowableCollateralMarkets.length;
    //         ++marketIndex
    //     ) {
    //         if (snapshotId > 0) vm.revertTo(snapshotId);
    //         snapshotId = vm.snapshot();

    //         TestMarket memory market = borrowableCollateralMarkets[marketIndex];

    //         (, uint256 expectedSupply, uint256 expectedBorrow) = fold(market);

    //         (, , uint256 totalSupply) = LENS.getCurrentSupplyBalanceInOf(
    //             market.poolToken,
    //             address(user)
    //         );
    //         (, , uint256 totalBorrow) = LENS.getCurrentBorrowBalanceInOf(
    //             market.poolToken,
    //             address(user)
    //         );
    //         uint256 healthFactor = LENS.getUserHealthFactor(address(user));

    //         assertApproxEqAbs(
    //             totalSupply,
    //             expectedSupply,
    //             expectedSupply / 1e6 + 10,
    //             "unexpected total supply"
    //         );
    //         assertApproxEqAbs(
    //             totalBorrow,
    //             expectedBorrow,
    //             expectedBorrow / 1e6 + 10,
    //             "unexpected total borrow"
    //         );

    //         assertApproxEqAbs(
    //             healthFactor,
    //             market.liquidationThreshold.wadDiv(market.ltv).percentAdd(1),
    //             1e17, // TODO: high margin to explain
    //             "unexpected health factor"
    //         );
    //     }
    // }

    // function testShouldNotFoldBorrowableCollateralMarketAboveCollateralFactor()
    //     public
    // {
    //     for (
    //         uint256 marketIndex;
    //         marketIndex < borrowableCollateralMarkets.length;
    //         ++marketIndex
    //     ) {
    //         TestMarket memory market = borrowableCollateralMarkets[marketIndex];
    //         uint256 amount = ERC20(market.underlying).balanceOf(address(user));

    //         IMainnetMorphoTxBuilder.ActionType[]
    //             memory actions = new IMainnetMorphoTxBuilder.ActionType[](3);
    //         bytes[] memory data = new bytes[](actions.length);

    //         (actions[0], data[0]) = user.encodeApprove(
    //             market.underlying,
    //             address(MORPHO),
    //             amount
    //         );
    //         (actions[1], data[1]) = user.encodeSupply(market.poolToken, amount);
    //         (actions[2], data[2]) = user.encodeBorrow(
    //             market.poolToken,
    //             amount.percentMul(market.ltv).percentAdd(1)
    //         );

    //         vm.expectRevert(0xdf9db463); // UnauthorisedBorrow.selector
    //         user.execute(actions, data);
    //     }
    // }

    // function testShouldUnfoldBorrowableCollateralMarketToReceiver() public {
    //     for (
    //         uint256 marketIndex;
    //         marketIndex < borrowableCollateralMarkets.length;
    //         ++marketIndex
    //     ) {
    //         if (snapshotId > 0) vm.revertTo(snapshotId);
    //         snapshotId = vm.snapshot();

    //         TestMarket memory market = borrowableCollateralMarkets[marketIndex];

    //         (uint256 initialAmount, , ) = fold(market);

    //         vm.roll(block.number + 10_000);

    //         /// UNFOLDING

    //         (, , uint256 totalBorrowBefore) = LENS.getCurrentBorrowBalanceInOf(
    //             market.poolToken,
    //             address(user)
    //         );

    //         uint256 amount = ERC20(market.underlying).balanceOf(address(user));

    //         IMainnetMorphoTxBuilder.ActionType[]
    //             memory actions = new IMainnetMorphoTxBuilder.ActionType[](
    //                 FOLDING_STEPS * 2 + 3
    //             );
    //         bytes[] memory data = new bytes[](actions.length);

    //         (actions[0], data[0]) = user.encodeApprove(
    //             market.underlying,
    //             address(MORPHO),
    //             totalBorrowBefore.percentAdd(5)
    //         );

    //         for (uint256 i; i < FOLDING_STEPS; i++) {
    //             (actions[2 * i + 1], data[2 * i + 1]) = user.encodeRepay(
    //                 market.poolToken,
    //                 amount
    //             );

    //             amount = amount.percentDiv(market.ltv).percentSub(1);
    //             (actions[2 * i + 2], data[2 * i + 2]) = user.encodeWithdraw(
    //                 market.poolToken,
    //                 amount
    //             );
    //         }

    //         // Last step to repay & withdraw interests
    //         (actions[2 * FOLDING_STEPS + 1], data[2 * FOLDING_STEPS + 1]) = user
    //             .encodeRepay(market.poolToken, type(uint256).max);
    //         (actions[2 * FOLDING_STEPS + 2], data[2 * FOLDING_STEPS + 2]) = user
    //             .encodeWithdraw(
    //                 market.poolToken,
    //                 address(0xDECAFC0FFEE),
    //                 type(uint256).max,
    //                 IMainnetMorphoTxBuilder.OpType.RAW
    //             );

    //         user.execute(actions, data);

    //         (, , uint256 totalSupply) = LENS.getCurrentSupplyBalanceInOf(
    //             market.poolToken,
    //             address(user)
    //         );
    //         (, , uint256 totalBorrow) = LENS.getCurrentBorrowBalanceInOf(
    //             market.poolToken,
    //             address(user)
    //         );

    //         uint256 receiverBalance = ERC20(market.underlying).balanceOf(
    //             address(0xDECAFC0FFEE)
    //         );
    //         assertGt(receiverBalance, 0, "unexpected total borrow");

    //         assertEq(totalSupply, 0, "unexpected total supply");
    //         assertEq(totalBorrow, 0, "unexpected total borrow");
    //         assertApproxEqAbs(
    //             ERC20(market.underlying).balanceOf(address(user)) +
    //                 receiverBalance,
    //             initialAmount,
    //             initialAmount / 1e6,
    //             "unexpected underlying balance"
    //         );
    //     }
    // }

    // function leverage(
    //     TestMarket memory collateralMarket,
    //     TestMarket memory borrowedMarket
    // ) public returns (LeverageTest memory test) {
    //     test.borrowedPrice = oracle.getAssetPrice(borrowedMarket.underlying);
    //     test.collateralPrice = oracle.getAssetPrice(
    //         collateralMarket.underlying
    //     );
    //     test.collateralBorrowedPrice = (test.collateralPrice *
    //         10**borrowedMarket.decimals).wadDiv(
    //             test.borrowedPrice * 10**collateralMarket.decimals
    //         );

    //     test.collateralMultiplier = (collateralMarket.ltv * 1e14) // ltv is in bps but collateralMultiplier is expected in WAD
    //         .wadMul(test.collateralBorrowedPrice)
    //         .wadMul(0.999e18); // small ltv margin

    //     test.initialCollateralAmount = ERC20(collateralMarket.underlying)
    //         .balanceOf(address(user));
    //     test.initialBorrowedAmount = test.initialCollateralAmount.wadMul(
    //         test.collateralMultiplier
    //     );

    //     IMainnetMorphoTxBuilder.ActionType[]
    //         memory actions = new IMainnetMorphoTxBuilder.ActionType[](
    //             LEVERAGE_STEPS * 3 + 2
    //         );
    //     bytes[] memory data = new bytes[](actions.length);

    //     (actions[0], data[0]) = user.encodeApprove(
    //         collateralMarket.underlying,
    //         address(MORPHO),
    //         test.initialCollateralAmount * LEVERAGE_STEPS
    //     );
    //     (actions[1], data[1]) = user.encodeApprove(
    //         borrowedMarket.underlying,
    //         UNISWAP_V3_ROUTER,
    //         test.initialBorrowedAmount * LEVERAGE_STEPS
    //     );

    //     for (uint256 i; i < LEVERAGE_STEPS; i++) {
    //         test.leverageMultiplier =
    //             1e18 +
    //             test.leverageMultiplier.percentMul(collateralMarket.ltv);

    //         (actions[3 * i + 2], data[3 * i + 2]) = i > 0
    //             ? user.encodeSupply(
    //                 collateralMarket.poolToken,
    //                 0,
    //                 IMainnetMorphoTxBuilder.OpType.ADD
    //             )
    //             : user.encodeSupply(
    //                 collateralMarket.poolToken,
    //                 test.initialCollateralAmount,
    //                 IMainnetMorphoTxBuilder.OpType.RAW
    //             );

    //         (actions[3 * i + 3], data[3 * i + 3]) = i > 0
    //             ? user.encodeBorrow(
    //                 borrowedMarket.poolToken,
    //                 test.collateralMultiplier,
    //                 IMainnetMorphoTxBuilder.OpType.MUL
    //             )
    //             : user.encodeBorrow(
    //                 borrowedMarket.poolToken,
    //                 test.initialBorrowedAmount,
    //                 IMainnetMorphoTxBuilder.OpType.RAW
    //             );

    //         (actions[3 * i + 4], data[3 * i + 4]) = user.encodeSwapExactIn(
    //             borrowedMarket.underlying,
    //             collateralMarket.underlying,
    //             0,
    //             test.collateralBorrowedPrice,
    //             MAX_SLIPPAGE_BPS,
    //             IMainnetMorphoTxBuilder.OpType.ADD
    //         );
    //     }

    //     user.execute(actions, data);
    // }

    // function testShouldLeverageActiveMarketWithCollateralMarket() public {
    //     for (
    //         uint256 collateralMarketIndex;
    //         collateralMarketIndex < collateralMarkets.length;
    //         ++collateralMarketIndex
    //     ) {
    //         for (
    //             uint256 borrowedMarketIndex;
    //             borrowedMarketIndex < activeMarkets.length;
    //             ++borrowedMarketIndex
    //         ) {
    //             if (snapshotId > 0) vm.revertTo(snapshotId);
    //             snapshotId = vm.snapshot();

    //             TestMarket memory collateralMarket = collateralMarkets[
    //                 collateralMarketIndex
    //             ];
    //             TestMarket memory borrowedMarket = activeMarkets[
    //                 borrowedMarketIndex
    //             ];
    //             if (collateralMarket.poolToken == borrowedMarket.poolToken)
    //                 continue;

    //             uint256 borrowedBalanceBefore = ERC20(borrowedMarket.underlying)
    //                 .balanceOf(address(user));

    //             LeverageTest memory test = leverage(
    //                 collateralMarket,
    //                 borrowedMarket
    //             );

    //             (, , uint256 totalSupply) = LENS.getCurrentSupplyBalanceInOf(
    //                 collateralMarket.poolToken,
    //                 address(user)
    //             );
    //             (, , uint256 totalBorrow) = LENS.getCurrentBorrowBalanceInOf(
    //                 borrowedMarket.poolToken,
    //                 address(user)
    //             );
    //             uint256 healthFactor = LENS.getUserHealthFactor(address(user));

    //             uint256 expectedSupply = test.initialCollateralAmount.wadMul(
    //                 test.leverageMultiplier
    //             );
    //             uint256 expectedBorrow = (expectedSupply -
    //                 test.initialCollateralAmount).wadMul(
    //                     test.collateralBorrowedPrice
    //                 );

    //             assertEq(
    //                 borrowedBalanceBefore,
    //                 ERC20(borrowedMarket.underlying).balanceOf(address(user)),
    //                 "unexpected borrowed balance"
    //             );
    //             assertApproxEqAbs(
    //                 totalSupply,
    //                 expectedSupply,
    //                 expectedSupply.percentMul(MAX_SLIPPAGE_BPS),
    //                 "unexpected total supply"
    //             );
    //             assertApproxEqAbs(
    //                 totalBorrow,
    //                 expectedBorrow,
    //                 expectedBorrow.percentMul(MAX_SLIPPAGE_BPS),
    //                 "unexpected total borrow"
    //             );
    //             assertApproxEqAbs(
    //                 healthFactor,
    //                 collateralMarket
    //                     .liquidationThreshold
    //                     .wadDiv(collateralMarket.ltv)
    //                     .percentDiv(99_90),
    //                 1e15,
    //                 "unexpected health factor"
    //             );
    //         }
    //     }
    // }

    // function testShouldDeleverageActiveMarketWithCollateralMarketToReceiver()
    //     public
    // {
    //     for (
    //         uint256 collateralMarketIndex;
    //         collateralMarketIndex < collateralMarkets.length;
    //         ++collateralMarketIndex
    //     ) {
    //         for (
    //             uint256 borrowedMarketIndex;
    //             borrowedMarketIndex < activeMarkets.length;
    //             ++borrowedMarketIndex
    //         ) {
    //             if (snapshotId > 0) vm.revertTo(snapshotId);
    //             snapshotId = vm.snapshot();

    //             TestMarket memory collateralMarket = collateralMarkets[
    //                 collateralMarketIndex
    //             ];
    //             TestMarket memory borrowedMarket = activeMarkets[
    //                 borrowedMarketIndex
    //             ];
    //             if (collateralMarket.poolToken == borrowedMarket.poolToken)
    //                 continue;

    //             LeverageTest memory test = leverage(
    //                 collateralMarket,
    //                 borrowedMarket
    //             );

    //             vm.roll(block.number + 10_000);

    //             /// DELEVERAGE

    //             (, , test.totalSupplyBefore) = LENS.getCurrentSupplyBalanceInOf(
    //                 collateralMarket.poolToken,
    //                 address(user)
    //             );
    //             (, , test.totalBorrowBefore) = LENS.getCurrentBorrowBalanceInOf(
    //                 borrowedMarket.poolToken,
    //                 address(user)
    //             );

    //             uint256 amount = ERC20(collateralMarket.underlying).balanceOf(
    //                 address(user)
    //             );

    //             IMainnetMorphoTxBuilder.ActionType[]
    //                 memory actions = new IMainnetMorphoTxBuilder.ActionType[](
    //                     LEVERAGE_STEPS * 3 + 5
    //                 );
    //             bytes[] memory data = new bytes[](actions.length);

    //             (actions[0], data[0]) = user.encodeApprove(
    //                 borrowedMarket.underlying,
    //                 address(MORPHO),
    //                 test.totalBorrowBefore.percentAdd(MAX_SLIPPAGE_BPS)
    //             );
    //             (actions[1], data[1]) = user.encodeApprove(
    //                 collateralMarket.underlying,
    //                 UNISWAP_V3_ROUTER,
    //                 test.totalSupplyBefore.percentAdd(MAX_SLIPPAGE_BPS)
    //             );

    //             uint256 borrowedCollateralPrice = uint256(1e18).wadDiv(
    //                 test.collateralBorrowedPrice
    //             );
    //             for (uint256 i; i < LEVERAGE_STEPS; i++) {
    //                 (actions[3 * i + 2], data[3 * i + 2]) = i > 0
    //                     ? user.encodeSwapExactIn(
    //                         collateralMarket.underlying,
    //                         borrowedMarket.underlying,
    //                         0,
    //                         borrowedCollateralPrice,
    //                         MAX_SLIPPAGE_BPS,
    //                         IMainnetMorphoTxBuilder.OpType.ADD
    //                     )
    //                     : user.encodeSwapExactIn(
    //                         collateralMarket.underlying,
    //                         borrowedMarket.underlying,
    //                         amount,
    //                         borrowedCollateralPrice,
    //                         MAX_SLIPPAGE_BPS,
    //                         IMainnetMorphoTxBuilder.OpType.RAW
    //                     );

    //                 (actions[3 * i + 3], data[3 * i + 3]) = user.encodeRepay(
    //                     borrowedMarket.poolToken,
    //                     0,
    //                     IMainnetMorphoTxBuilder.OpType.ADD
    //                 );

    //                 (actions[3 * i + 4], data[3 * i + 4]) = user.encodeWithdraw(
    //                     collateralMarket.poolToken,
    //                     uint256(0.98e18).wadDiv(test.collateralMultiplier),
    //                     IMainnetMorphoTxBuilder.OpType.MUL
    //                 );
    //             }

    //             // Last step to repay & withdraw all (because of slippage)
    //             (
    //                 actions[3 * LEVERAGE_STEPS + 2],
    //                 data[3 * LEVERAGE_STEPS + 2]
    //             ) = user.encodeSwapExactIn(
    //                 collateralMarket.underlying,
    //                 borrowedMarket.underlying,
    //                 0,
    //                 borrowedCollateralPrice,
    //                 MAX_SLIPPAGE_BPS,
    //                 IMainnetMorphoTxBuilder.OpType.ADD
    //             );
    //             (
    //                 actions[3 * LEVERAGE_STEPS + 3],
    //                 data[3 * LEVERAGE_STEPS + 3]
    //             ) = user.encodeRepay(
    //                 borrowedMarket.poolToken,
    //                 type(uint256).max
    //             );
    //             (
    //                 actions[3 * LEVERAGE_STEPS + 4],
    //                 data[3 * LEVERAGE_STEPS + 4]
    //             ) = user.encodeWithdraw(
    //                 collateralMarket.poolToken,
    //                 address(0xDECAFC0FFEE),
    //                 type(uint256).max,
    //                 IMainnetMorphoTxBuilder.OpType.RAW
    //             );

    //             user.execute(actions, data);

    //             (, , uint256 totalSupply) = LENS.getCurrentSupplyBalanceInOf(
    //                 collateralMarket.poolToken,
    //                 address(user)
    //             );
    //             (, , uint256 totalBorrow) = LENS.getCurrentBorrowBalanceInOf(
    //                 borrowedMarket.poolToken,
    //                 address(user)
    //             );
    //             assertEq(totalSupply, 0, "unexpected total supply");
    //             assertEq(totalBorrow, 0, "unexpected total borrow");

    //             uint256 receiverBalance = ERC20(collateralMarket.underlying)
    //                 .balanceOf(address(0xDECAFC0FFEE));
    //             assertGt(receiverBalance, 0, "unexpected receiver balance");

    //             uint256 usdcPrice = oracle.getAssetPrice(USDC);
    //             uint256 totalUsd = ((ERC20(borrowedMarket.underlying).balanceOf(
    //                 address(user)
    //             ) *
    //                 test.borrowedPrice *
    //                 1e18) / (usdcPrice * 10**borrowedMarket.decimals)) +
    //                 ((ERC20(collateralMarket.underlying).balanceOf(
    //                     address(user)
    //                 ) + receiverBalance) *
    //                     test.collateralPrice *
    //                     1e18) /
    //                 (usdcPrice * 10**collateralMarket.decimals);

    //             assertGt(
    //                 totalUsd,
    //                 (2 * INITIAL_USD_BALANCE).percentSub(MAX_SLIPPAGE_BPS),
    //                 "lower total usd balance than expected"
    //             );
    //             assertLt(
    //                 totalUsd,
    //                 2 * INITIAL_USD_BALANCE,
    //                 "greater total usd balance than expected"
    //             );
    //         }
    //     }
    // }

    function _getApproveData(
        uint256 privateKey,
        address underlying,
        uint160 amount,
        uint48 deadline,
        IBulkerGateway.OpType op
    ) internal view returns (IBulkerGateway.ActionType action, bytes memory data) {
        address delegator = vm.addr(privateKey);
        action = IBulkerGateway.ActionType.APPROVE2;

        (,, uint48 nonce) = PERMIT2.allowance(delegator, underlying, address(bulker));
        IAllowanceTransfer.PermitDetails memory details =
            IAllowanceTransfer.PermitDetails({token: underlying, amount: amount, expiration: deadline, nonce: nonce});
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: address(bulker), sigDeadline: deadline});

        Types.Signature memory sig;

        bytes32 hashed = PermitHash.hash(permitSingle);
        hashed = ECDSA.toTypedDataHash(PERMIT2.DOMAIN_SEPARATOR(), hashed);

        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);
        data = abi.encode(underlying, amount, deadline, sig, op);
    }

    function _getTransferFromData(address asset, uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.TRANSFER_FROM2;
        data = abi.encode(asset, amount, op);
    }

    function _getApproveManagerData(uint256 privateKey, bool isAllowed, uint256 deadline)
        internal
        view
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        address delegator = vm.addr(privateKey);
        action = IBulkerGateway.ActionType.APPROVE_MANAGER;

        uint256 nonce = morpho.userNonce(delegator);
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            delegator: delegator,
            manager: address(bulker),
            isAllowed: isAllowed,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 hashed = sigUtils.getTypedDataHash(authorization);

        Types.Signature memory sig;

        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);
        data = abi.encode(isAllowed, nonce, deadline, sig);
    }

    function _getSupplyData(
        address asset,
        uint256 amount,
        address onBehalf,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.SUPPLY;
        data = abi.encode(asset, amount, onBehalf, maxIterations, op);
    }

    function _getSupplyCollateralData(address asset, uint256 amount, address onBehalf, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.SUPPLY_COLLATERAL;
        data = abi.encode(asset, amount, onBehalf, op);
    }

    function _getBorrowData(
        address asset,
        uint256 amount,
        address receiver,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.BORROW;
        data = abi.encode(asset, amount, receiver, maxIterations, op);
    }

    function _getRepayData(address asset, uint256 amount, address onBehalf, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.REPAY;
        data = abi.encode(asset, amount, onBehalf, op);
    }

    function _getWithdrawData(
        address asset,
        uint256 amount,
        address receiver,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.WITHDRAW;
        data = abi.encode(asset, amount, receiver, maxIterations, op);
    }

    function _getWithdrawCollateralData(address asset, uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WITHDRAW_COLLATERAL;
        data = abi.encode(asset, amount, receiver, op);
    }

    function _getClaimRewardsData(address[] memory assets, address onBehalf)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.CLAIM_REWARDS;
        data = abi.encode(assets, onBehalf);
    }

    function _getWrapETHData(uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WRAP_ETH;
        data = abi.encode(amount, op);
    }

    function _getUnwrapETHData(uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.UNWRAP_ETH;
        data = abi.encode(amount, receiver, op);
    }

    function _getWrapStETHData(uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WRAP_ST_ETH;
        data = abi.encode(amount, op);
    }

    function _getUnwrapStETHData(uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.UNWRAP_ST_ETH;
        data = abi.encode(amount, receiver, op);
    }
}
