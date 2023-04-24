pragma solidity >=0.5.0;

interface ITokenBuyer {
    function buyToken(address _token, address _to) external payable returns (uint256);
    function busdToUFI(uint256 _amountBUSD) external view returns (uint256,uint256); //returns (amount WBNB, amount UFI)
    function buyExactTokens(uint256 _amountToken, address _to) external payable;
}
