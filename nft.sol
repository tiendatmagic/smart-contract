// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721URIStorage, Ownable {
    uint256 private _currentTokenId;
    string private _fixedTokenURI;

    /**
     * @dev Constructor to initialize the NFT contract with a name, symbol, and fixed token URI.
     * @param initialOwner Address of the initial owner.
     * @param fixedTokenURI The IPFS URI for the token metadata.
     */
    constructor(address initialOwner, string memory fixedTokenURI)
        ERC721("Wrapper MyNFT", "MyNFT")
        Ownable(initialOwner)
    {
        _fixedTokenURI = fixedTokenURI;
    }

    /**
     * @dev Mint a new NFT to the specified address with the fixed token URI.
     * @param to Address to receive the NFT.
     */
    function mint(address to) public onlyOwner {
        // Increment the token ID counter
        _currentTokenId++;

        // Mint the NFT to the specified address
        _safeMint(to, _currentTokenId);

        // Set the fixed token URI for the newly minted NFT
        _setTokenURI(_currentTokenId, _fixedTokenURI);
    }

    /**
     * @dev Get the current token ID.
     * @return The current token ID.
     */
    function getCurrentTokenId() public view returns (uint256) {
        return _currentTokenId;
    }

    /**
     * @dev Get the fixed token URI.
     * @return The fixed token URI.
     */
    function getFixedTokenURI() public view returns (string memory) {
        return _fixedTokenURI;
    }

    function transferToken(
        address from,
        address to,
        uint256 tokenId
    ) public onlyOwner {
        require(
            ownerOf(tokenId) == from,
            "From address is not the owner of the token"
        );

        _transfer(from, to, tokenId);
    }
}
