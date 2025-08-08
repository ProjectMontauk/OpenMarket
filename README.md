#taco
I kept the repo private so please let me know which emails need access and I can add them as collaborators
There are a couple of debugging functions still in the code which I’d like to keep for now
The in-scope contracts are in the contracts folder and all five are mentioned below
ABDKMath64x64.sol & CTHelpers.sol are mathematical helper functions
FakeDai.sol is a standard test ERC-20 token contract 
ConditionalTokens.sol manages the ERC-1155 outcome tokens
NoBOverround.sol manages the market making operations 
I’m still working on building out test cases which I will submit when it comes time for the actual audit
The code is going to be deployed on the Base network
The TestDai.sol contract will be replaced by USDC in the final version 
ThirdWeb RPC is used to execute contract functions and interact with data in the app
