// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPositionsManager} from "src/interfaces/IPositionsManager.sol";

import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Morpho} from "src/Morpho.sol";
import {PositionsManager} from "src/PositionsManager.sol";
import {RewardsManagerMock} from "test/mocks/RewardsManagerMock.sol";
import {UserMock} from "test/mocks/UserMock.sol";
import "./ForkTest.sol";

contract UnitTest is ForkTest {
    uint8 internal constant E_MODE_CATEGORY_ID = 0;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    RewardsManagerMock internal rewardsManagerMock;

    function setUp() public virtual override {
        positionsManager = new PositionsManager(address(addressesProvider), E_MODE_CATEGORY_ID);
        morphoImpl = new Morpho(address(addressesProvider), E_MODE_CATEGORY_ID);

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(address(positionsManager), Types.Iterations({repay: 10, withdraw: 10}));

        super.setUp();
    }
}
