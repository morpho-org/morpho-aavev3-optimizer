// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

import {SupplyVaultBase} from "src/extensions/SupplyVaultBase.sol";
import {SupplyVault} from "src/extensions/SupplyVault.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {SupplyVaultBaseMock} from "test/mocks/SupplyVaultBaseMock.sol";

contract TestSetupVaults is IntegrationTest {
    using SafeTransferLib for ERC20;

    address internal constant MORPHO_DAO = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;
    address internal constant RECIPIENT = 0x60345417a227ad7E312eAa1B5EC5CD1Fe5E2Cdc6;

    TransparentUpgradeableProxy internal wrappedNativeTokenSupplyVaultProxy;

    SupplyVault internal supplyVaultImplV1;

    SupplyVault internal wrappedNativeTokenSupplyVault;
    SupplyVault internal daiSupplyVault;
    SupplyVault internal usdcSupplyVault;
    SupplyVaultBase internal supplyVaultBase;

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
        supplyVaultImplV1 = new SupplyVault(address(morpho), RECIPIENT);
        supplyVaultBase = SupplyVaultBase(
            address(
                new TransparentUpgradeableProxy(
                    address(new SupplyVaultBaseMock(address(morpho), RECIPIENT)),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        wrappedNativeTokenSupplyVaultProxy = new TransparentUpgradeableProxy(
            address(supplyVaultImplV1),
            address(proxyAdmin),
            ""
        );
        wrappedNativeTokenSupplyVault = SupplyVault(address(wrappedNativeTokenSupplyVaultProxy));
        wrappedNativeTokenSupplyVault.initialize(wNative, "MorphoAaveWNATIVE", "maWNATIVE", 0, 4);
        maWrappedNativeToken = ERC20(address(wrappedNativeTokenSupplyVault));

        daiSupplyVault =
            SupplyVault(address(new TransparentUpgradeableProxy(address(supplyVaultImplV1), address(proxyAdmin), "")));
        daiSupplyVault.initialize(address(dai), "MorphoAaveDAI", "maDAI", 0, 4);
        maDai = ERC20(address(daiSupplyVault));

        usdcSupplyVault =
            SupplyVault(address(new TransparentUpgradeableProxy(address(supplyVaultImplV1), address(proxyAdmin), "")));
        usdcSupplyVault.initialize(address(usdc), "MorphoAaveUSDC", "maUSDC", 0, 4);
        maUsdc = ERC20(address(usdcSupplyVault));
    }

    function setVaultContractsLabels() internal {
        vm.label(address(wrappedNativeTokenSupplyVault), "SupplyVault (WNATIVE)");
        vm.label(address(usdcSupplyVault), "SupplyVault (USDC)");
        vm.label(address(daiSupplyVault), "SupplyVault (DAI)");
    }
}
