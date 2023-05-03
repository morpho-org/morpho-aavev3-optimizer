// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

import {SupplyVault} from "src/extensions/SupplyVault.sol";
import {ISupplyVault} from "src/interfaces/extensions/ISupplyVault.sol";

contract TestSetupVaults is IntegrationTest {
    using SafeTransferLib for ERC20;

    address internal constant MORPHO_DAO = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;
    address internal constant RECIPIENT = 0x60345417a227ad7E312eAa1B5EC5CD1Fe5E2Cdc6;

    TransparentUpgradeableProxy internal wrappedNativeTokenSupplyVaultProxy;

    SupplyVault internal supplyVaultImplWrappedNative;
    SupplyVault internal supplyVaultImplDai;
    SupplyVault internal supplyVaultImplUsdc;

    SupplyVault internal wrappedNativeTokenSupplyVault;
    SupplyVault internal daiSupplyVault;
    SupplyVault internal usdcSupplyVault;

    ERC20 internal maWrappedNativeToken;
    ERC20 internal maDai;
    ERC20 internal maUsdc;

    function setUp() public virtual override {
        super.setUp();
        morpho.setRewardsManager(_rewardsManager());
        initVaultContracts();
        setVaultContractsLabels();
    }

    function _rewardsManager() internal view virtual returns (address) {
        return address(0);
    }

    function initVaultContracts() internal {
        supplyVaultImplWrappedNative = new SupplyVault(address(morpho), wNative);
        supplyVaultImplDai = new SupplyVault(address(morpho), dai);
        supplyVaultImplUsdc = new SupplyVault(address(morpho), usdc);

        wrappedNativeTokenSupplyVaultProxy = new TransparentUpgradeableProxy(
            address(supplyVaultImplWrappedNative),
            address(proxyAdmin),
            ""
        );
        wrappedNativeTokenSupplyVault = SupplyVault(address(wrappedNativeTokenSupplyVaultProxy));
        wrappedNativeTokenSupplyVault.initialize(RECIPIENT, "MorphoAaveWNATIVE", "maWNATIVE", 0, 4);
        maWrappedNativeToken = ERC20(address(wrappedNativeTokenSupplyVault));

        daiSupplyVault =
            SupplyVault(address(new TransparentUpgradeableProxy(address(supplyVaultImplDai), address(proxyAdmin), "")));
        daiSupplyVault.initialize(RECIPIENT, "MorphoAaveDAI", "maDAI", 0, 4);
        maDai = ERC20(address(daiSupplyVault));

        usdcSupplyVault =
            SupplyVault(address(new TransparentUpgradeableProxy(address(supplyVaultImplUsdc), address(proxyAdmin), "")));
        usdcSupplyVault.initialize(RECIPIENT, "MorphoAaveUSDC", "maUSDC", 0, 4);
        maUsdc = ERC20(address(usdcSupplyVault));
    }

    function setVaultContractsLabels() internal {
        vm.label(address(wrappedNativeTokenSupplyVault), "SupplyVault (WNATIVE)");
        vm.label(address(usdcSupplyVault), "SupplyVault (USDC)");
        vm.label(address(daiSupplyVault), "SupplyVault (DAI)");
    }
}
