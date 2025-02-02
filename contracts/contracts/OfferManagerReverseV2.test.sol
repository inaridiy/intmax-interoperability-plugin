// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./OfferManagerReverseV2.sol";

contract OfferManagerReverseV2Test is OfferManagerReverseV2 {
    constructor() {
        initialize();
    }

    /**
     * @dev This function registers a new offer.
     */
    function testRegister(
        bytes32 takerIntmaxAddress,
        address takerTokenAddress,
        uint256 takerAmount,
        address maker,
        bytes32 makerIntmaxAddress,
        uint256 makerAssetId,
        uint256 makerAmount
    ) external returns (uint256 flagId) {
        return
            _register(
                _msgSender(),
                takerIntmaxAddress,
                takerTokenAddress,
                takerAmount,
                maker,
                makerIntmaxAddress,
                makerAssetId,
                makerAmount
            );
    }

    /**
     * @dev This test function can activate the flag without actually making the transfer.
     * @param offerId is the ID of the offer.
     */
    function testActivate(uint256 offerId) external returns (bool) {
        _activate(offerId);

        return true;
    }
}
