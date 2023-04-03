// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./OfferManagerReverseInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "hardhat/console.sol";

contract OfferManagerReverse is OfferManagerReverseInterface {
    /**
     * @dev Struct representing an offer created by a maker and taken by a taker.
     * @param maker is the address of the maker who creates the offer.
     * @param makerIntmaxAddress is the intmax address of the maker.
     * @param makerAssetId is the asset ID that the maker is selling to the taker.
     * @param makerAmount is the amount of the asset that the maker is selling to the taker.
     * @param taker is the address of the taker who takes the offer.
     * @param takerIntmaxAddress is the intmax address of the taker.
     * @param takerTokenAddress is the address of the token that the taker needs to pay.
     * @param takerAmount is the amount of the token that the taker needs to pay.
     * @param isActivated is a boolean flag indicating whether the offer is activated or not.
     */
    struct Offer {
        address maker;
        bytes32 makerIntmaxAddress;
        uint256 makerAssetId;
        uint256 makerAmount;
        address taker;
        bytes32 takerIntmaxAddress;
        address takerTokenAddress;
        uint256 takerAmount;
        bool isActivated;
    }

    // uint256 constant MAX_ASSET_ID = 18446744069414584320; // the maximum value of Goldilocks field
    uint256 constant MAX_REMITTANCE_AMOUNT = 18446744069414584320; // the maximum value of Goldilocks field
    address immutable OWNER_ADDRESS;

    /**
     * @dev This is the ID allocated to the next offer data to be registered.
     */
    uint256 public nextOfferId = 0;

    /**
     * @dev This is the mapping from offer ID to offer data.
     */
    mapping(uint256 => Offer) _offers;

    constructor() {
        OWNER_ADDRESS = msg.sender;
    }

    receive() external payable {}

    function register(
        bytes32 takerIntmaxAddress,
        address takerTokenAddress,
        uint256 takerAmount,
        address maker,
        uint256 makerAssetId,
        uint256 makerAmount
    ) external payable returns (uint256 offerId) {
        require(_checkMaker(maker), "`maker` must not be zero.");

        // Check if given `takerTokenAddress` is either ETH or ERC20.
        if (takerTokenAddress == address(0)) {
            require(
                msg.value == takerAmount,
                "takerAmount must be the same as msg.value"
            );
        } else {
            require(
                msg.value == 0,
                "transmission method other than ETH is specified"
            );
            bool success = IERC20(takerTokenAddress).transferFrom(
                msg.sender,
                address(this),
                takerAmount
            );
            require(success, "fail to transfer ERC20 token");
        }

        // require(
        //     makerIntmaxAddress == bytes32(0),
        //     "`makerIntmaxAddress` must be zero"
        // );

        return
            _register(
                msg.sender, // taker
                takerIntmaxAddress,
                takerTokenAddress,
                msg.value, // takerAmount
                maker,
                bytes32(0), // anyone activates this offer
                makerAssetId,
                makerAmount
            );
    }

    function updateMaker(uint256 offerId, address newMaker) external {
        // The offer must exist.
        require(
            isRegistered(offerId),
            "This offer ID has not been registered."
        );

        // Caller must have the permission to update the offer.
        require(
            msg.sender == _offers[offerId].taker,
            "Offers can be updated by its taker."
        );

        require(_checkMaker(newMaker), "`newMaker` should not be zero.");

        _offers[offerId].maker = newMaker;

        emit OfferMakerUpdated(offerId, newMaker);
    }

    function checkWitness(
        uint256 offerId,
        bytes calldata witness
    ) external view returns (bool) {
        Offer memory offer = _offers[offerId];

        bytes32 hashedMessage = ECDSA.toEthSignedMessageHash(
            offer.takerIntmaxAddress
        );
        _checkWitness(hashedMessage, witness);

        return true;
    }

    function activate(
        uint256 offerId,
        bytes calldata witness
    ) external returns (bool) {
        Offer memory offer = _offers[offerId];

        // address makerIntmaxAddress = _offers[offerId].makerIntmaxAddress;
        // if (makerIntmaxAddress != address(0)) {
        //     require(
        //         witness.senderIntmax == makerIntmaxAddress,
        //         "offers can be activated by its taker"
        //     );
        // }

        bytes32 hashedMessage = ECDSA.toEthSignedMessageHash(
            offer.takerIntmaxAddress
        );
        _checkWitness(hashedMessage, witness);

        require(
            msg.sender == offer.maker,
            "Only the maker can unlock this offer."
        );
        _markOfferAsActivated(offerId);

        // The maker transfers token to taker.
        payable(offer.maker).transfer(offer.takerAmount);
        if (offer.takerTokenAddress == address(0)) {
            payable(offer.maker).transfer(offer.takerAmount);
        } else {
            bool success = IERC20(offer.takerTokenAddress).transfer(
                offer.maker,
                offer.takerAmount
            );
            require(success, "fail to transfer ERC20 token");
        }

        return true;
    }

    function getOffer(
        uint256 offerId
    )
        public
        view
        returns (
            address maker,
            bytes32 makerIntmaxAddress,
            uint256 makerAssetId,
            uint256 makerAmount,
            address taker,
            bytes32 takerIntmaxAddress,
            address takerTokenAddress,
            uint256 takerAmount,
            bool activated
        )
    {
        Offer storage offer = _offers[offerId];
        maker = offer.maker;
        makerIntmaxAddress = offer.makerIntmaxAddress;
        makerAssetId = offer.makerAssetId;
        makerAmount = offer.makerAmount;
        taker = offer.taker;
        takerIntmaxAddress = offer.takerIntmaxAddress;
        takerTokenAddress = offer.takerTokenAddress;
        takerAmount = offer.takerAmount;
        activated = offer.isActivated;
    }

    function isRegistered(uint256 offerId) public view returns (bool) {
        return (_offers[offerId].taker != address(0));
    }

    function isActivated(uint256 offerId) public view returns (bool) {
        return _offers[offerId].isActivated;
    }

    /**
     * @dev Accepts an offer from a maker and registers it with a new offer ID.
     * @param taker is the address of the taker.
     * @param takerIntmaxAddress is the intmax address of the taker.
     * @param takerTokenAddress is the address of the token the taker will transfer.
     * @param takerAmount is the amount of token the taker will transfer.
     * @param maker is the address of the maker.
     * @param makerIntmaxAddress is the intmax address of the maker.
     * @param makerAssetId is the ID of the asset the maker will transfer on intmax.
     * @param makerAmount is the amount of asset the maker will transfer on intmax.
     * @return offerId is the ID of the newly registered offer.
     *
     * Requirements:
     * - The taker must not be the zero address.
     * - The offer ID must not be already registered.
     * - The maker's offer amount must be less than or equal to MAX_REMITTANCE_AMOUNT.
     */
    function _register(
        address taker,
        bytes32 takerIntmaxAddress,
        address takerTokenAddress,
        uint256 takerAmount,
        address maker,
        bytes32 makerIntmaxAddress,
        uint256 makerAssetId,
        uint256 makerAmount
    ) internal returns (uint256 offerId) {
        require(taker != address(0), "The taker must not be zero address.");
        offerId = nextOfferId;
        require(!isRegistered(offerId), "Offer ID already registered.");

        Offer memory offer = Offer({
            taker: taker,
            takerIntmaxAddress: takerIntmaxAddress,
            takerTokenAddress: takerTokenAddress,
            takerAmount: takerAmount,
            maker: maker,
            makerIntmaxAddress: makerIntmaxAddress,
            makerAssetId: makerAssetId,
            makerAmount: makerAmount,
            isActivated: false
        });

        _isValidOffer(offer);
        _offers[offerId] = offer;
        nextOfferId += 1;
        emit OfferRegistered(
            offerId,
            taker,
            takerIntmaxAddress,
            takerTokenAddress,
            takerAmount,
            makerIntmaxAddress,
            makerAssetId,
            makerAmount
        );
        emit OfferMakerUpdated(offerId, maker);
    }

    /**
     * @dev Marks the offer as activated.
     * @param offerId is the ID of the offer.
     */
    function _markOfferAsActivated(uint256 offerId) internal {
        require(
            isRegistered(offerId),
            "This offer ID has not been registered."
        );
        require(!isActivated(offerId), "This offer ID is already activated.");
        _offers[offerId].isActivated = true;
    }

    /**
     * This function activates a offer and emits an `Unlock` event.
     * @param offerId is the ID of the offer to be unlocked.
     */
    function _activate(uint256 offerId) internal {
        _markOfferAsActivated(offerId);
        emit OfferActivated(offerId, _offers[offerId].maker);
    }

    /**
     * @dev Verify the validity of the witness signature.
     * @param hashedMessage is the hash of the message that the signature corresponds to.
     * @param signature is the signature that needs to be verified.
     *
     * Requirements:
     * - The recovered signer from the signature must be the same as the owner address.
     */
    function _checkWitness(
        bytes32 hashedMessage,
        bytes memory signature
    ) internal view virtual {
        address signer = ECDSA.recover(hashedMessage, signature);
        require(signer == OWNER_ADDRESS, "Fail to verify signature.");
    }

    /**
     * @dev Verify the validity of the offer.
     * @param offer is the offer that needs to be verified.
     *
     * Requirements:
     * - The `makerAmount` in the offer must be less than or equal to `MAX_REMITTANCE_AMOUNT`.
     */
    function _isValidOffer(Offer memory offer) internal pure {
        require(
            offer.makerAmount <= MAX_REMITTANCE_AMOUNT,
            "Invalid offer amount: exceeds maximum remittance amount."
        );
        // require(
        //     offer.makerAmount > 0,
        //     "Maker amount must be greater than zero"
        // );
        // require(
        //     offer.takerAmount > 0,
        //     "Taker amount must be greater than zero"
        // );
    }

    function _checkMaker(address maker) internal pure returns (bool) {
        // A maker should not be the zero address.
        return maker != address(0);
    }
}
