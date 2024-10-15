// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Errors} from "@aave-v3-origin/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "@aave-v3-origin/protocol/libraries/types/DataTypes.sol";

/// @title ReserveConfigurationLegacy
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library used to ease AaveV3's legacy reserve configuration calculations.
library ReserveConfigurationLegacy {
    uint256 internal constant EMODE_CATEGORY_START_BIT_POSITION = 168;
    uint256 internal constant EMODE_CATEGORY_MASK = 0xFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MAX_VALID_EMODE_CATEGORY = 255;

    function getEModeCategory(DataTypes.ReserveConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~EMODE_CATEGORY_MASK) >> EMODE_CATEGORY_START_BIT_POSITION;
    }

    function setEModeCategory(DataTypes.ReserveConfigurationMap memory self, uint256 category) internal pure {
        require(category <= MAX_VALID_EMODE_CATEGORY, Errors.INVALID_EMODE_CATEGORY);

        self.data = (self.data & EMODE_CATEGORY_MASK) | (category << EMODE_CATEGORY_START_BIT_POSITION);
    }
}
