// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

abstract contract IbtWrapper {
    function rebaseIndex() external view virtual returns (uint256);
}
