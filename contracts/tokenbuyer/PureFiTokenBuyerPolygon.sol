pragma solidity ^0.8.0;


import "../interfaces/uniswap/RouterInterface.sol";
import "../interfaces/uniswap/IUniswapV2Pair.sol";
import "../../openzeppelin-contracts-master/contracts/access/Ownable.sol";
import "./ITokenBuyer.sol";

contract PureFiTokenBuyerPolygon is Ownable, ITokenBuyer {
    uint16 public constant PERCENT_DENOM = 10000;
    uint16 public slippage; //
    address targetToken; // UFI

    event TokenPurchase(address indexed who, uint256 bnbIn, uint256 ufiOut);

    constructor() {
        slippage = 100;
        targetToken = 0x3c205C8B3e02421Da82064646788c82f7bd753B9;
    }

    function changeSlippage(uint16 _slippage) public onlyOwner {
        require(_slippage <= PERCENT_DENOM, "Slippage too high");
        slippage = _slippage;
    }

    function routerAddress() public pure returns (address) {
        return 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    }

    function getPathUFI() internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        address wethAddress = IUniswapV2Router01(routerAddress()).WETH();
        path[0] = wethAddress;
        path[1] = targetToken; //ufi
        return path;
    }

    function buyToken(
        address _token,
        address _to
    ) external payable override returns (uint256) {
        if (_token == targetToken) {
            return _buyTokens(_to, getPathUFI());
        } else {
            revert("unknown token");
        }
    }

    function _buyTokens(
        address _to,
        address[] memory path
    ) internal returns (uint256) {
        IUniswapV2Router01 router = IUniswapV2Router01(routerAddress());

        uint[] memory amounts = router.getAmountsOut(msg.value, path);

        uint256 targetTokensExpected = amounts[amounts.length - 1];

        uint256 minTargetTokensExpected = (targetTokensExpected *
            (PERCENT_DENOM - slippage)) / PERCENT_DENOM;

        uint[] memory out = router.swapExactETHForTokens{value: msg.value}(
            minTargetTokensExpected,
            path,
            _to,
            block.timestamp
        );
        emit TokenPurchase(_to, out[0], out[out.length - 1]);

        return out[out.length - 1];
    }

    // USDC used insted of busd
    function busdToUFI(
        uint256 _amountUSD
    ) external view override returns (uint256, uint256) {
         //_amountUSD comes with 18 decimals to be compatible with implementations for other networks
         _amountUSD/=1e12; //converting to 6 decimals USDC standard in Ethereum

        address[] memory evaluatePath = new address[](3);
        evaluatePath[0] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // USDC
        evaluatePath[1] =  0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; //WETH ( Wrapped Matic in Polygon )
        evaluatePath[2] = targetToken; // UFI 

        uint256[] memory amounts = IUniswapV2Router01(routerAddress()).getAmountsOut(_amountUSD, evaluatePath);
        return (amounts[1], amounts[2]);
    }

    function buyExactTokens(
        uint256 _amountToken,
        address _to
    ) external payable override {
        address[] memory path = new address[](2);
        path[0] = IUniswapV2Router01(routerAddress()).WETH();
        path[1] = targetToken; // UFI
        (IUniswapV2Router01(routerAddress())).swapExactETHForTokens{value: msg.value}(_amountToken, path, _to, block.timestamp);
    }
}