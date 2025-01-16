// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721URIStorage, Ownable {
    uint256 private _currentTokenId;

    // Constructor to set the name and symbol of the NFT collection and the initial owner
    constructor(address initialOwner) ERC721("Magic NFT", "NFT") Ownable(initialOwner) {}

    /**
     * @dev Mint a new NFT to the specified address with a token URI.
     * @param to Address to receive the NFT.
     * @param tokenURI URI of the token's metadata.
     */
    function mint(address to, string memory tokenURI) public onlyOwner {
        // Increment the token ID counter
        _currentTokenId++;

        // Mint the NFT to the specified address
        _safeMint(to, _currentTokenId);

        // Set the token URI for the newly minted NFT
        _setTokenURI(_currentTokenId, tokenURI);
    }

    /**
     * @dev Get the current token ID.
     * @return The current token ID.
     */
    function getCurrentTokenId() public view returns (uint256) {
        return _currentTokenId;
    }
}
