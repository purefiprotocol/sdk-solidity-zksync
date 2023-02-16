// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IPureFiPlugin.sol";
import "./interfaces/UniswapV3/IUniswapV3Factory.sol";
import "./interfaces/UniswapV3/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/UniswapV3/ISwapRouter.sol";
import "./interfaces/UniswapV3/IWETH9.sol";

contract PureFiUniswapV3Plugin is AccessControl, IPureFiPlugin {
    IUniswapV3Factory uniswapV3Factory;
    ISwapRouter uniswapV3Router;
    address public paymaster;
    IWETH9 WETH;

    address[] whitelistedTokensArr;
    mapping(address => bool) public whitelistedTokensMap;
    mapping(address => uint24) public poolFees;

    event WhitelistToken( address indexed token, uint24 poolFee );
    event DelistToken( address indexed token );
    event SetPoolFee( address indexed token, uint24 indexed fee);

    constructor(
        address _admin,
        address _uniswapV3Router,
        address _uniswapV3Factory,
        address _paymaster,
        address _WETH,
        address[] memory _whitelistedTokens
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        paymaster = _paymaster;
        WETH = IWETH9(_WETH);
        whitelistedTokensArr = _whitelistedTokens;

        for (uint i = 0; i < _whitelistedTokens.length; i++) {
            whitelistedTokensMap[_whitelistedTokens[i]] = true;
        }
    }

    modifier onlyPaymaster() {
        require(
            msg.sender == paymaster,
            "PureFiUniswapV3Plugin : Only paymaster allowed"
        );
        _;
    }

    function version() external pure returns (uint256) {
        //xxx.yyy.zzz
        return 1000001;
    }


    function swapTokens() external onlyPaymaster returns (uint256 receivedETH) {
        uint256 receivedWETH = 0;
        for (uint i = 0; i < whitelistedTokensArr.length; i++) {
            uint256 whitelistedtokenBalance = IERC20(whitelistedTokensArr[i])
                .balanceOf(paymaster);
            require(
                IERC20(whitelistedTokensArr[i]).transferFrom(
                    paymaster,
                    address(this),
                    whitelistedtokenBalance
                ),
                "PureFiUniswapV3Plugin : tranferFrom fail"
            );

            uint256 minAmountOut = _getMinTokensAmount(
                whitelistedTokensArr[i],
                address(WETH),
                whitelistedtokenBalance,
                0
            );

            // uint256 minAmountOut = _getMinAmountOut(whitelistedTokens[i], );
            receivedWETH += _swapToken(whitelistedTokensArr[i], minAmountOut);
        }

        uint256 wethBalance = WETH.balanceOf(address(this));
        require(
            wethBalance == receivedWETH,
            "PureFiUniswapV3Plugin : Balances mismatching"
        );

        receivedETH = wethBalance;

        WETH.withdraw(wethBalance);

        (bool sent, ) = payable(paymaster).call{value: wethBalance}("");
        require(sent, "PureFiUniswapV3Plugin : Failed to send Ether");
    }

    function _swapToken(
        address _token,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOut) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "PureFiUniswapV3Plugin : Nothing to swap");

        // approve
        require(
            IERC20(_token).approve(address(uniswapV3Router), balance),
            "PureFiUniswapV3Plugin : Token approve fail"
        );

        // swap

        uint24 fee = _getPoolFee(_token);

        amountOut = uniswapV3Router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _token,
                tokenOut: address(WETH),
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 30,
                amountIn: balance,
                amountOutMinimum: _minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }


    // set pool fee for pair token/WETH
    function setPoolFee( address _token, uint24 _fee ) external onlyRole(DEFAULT_ADMIN_ROLE){
        // TODO : check for pool existance;
        require(_fee > 0, "PureFiUniswapV3Plugin : Incorrect fee value");
        poolFees[_token] = _fee;
    }

    function whitelistToken( address _token ) external onlyPaymaster returns (bool){
        whitelistedTokensMap[_token] = true;
        whitelistedTokensArr.push(_token);
        return true;

    }

    function delistToken( address _token ) external onlyPaymaster returns (bool){
        whitelistedTokensMap[_token] = false;
        uint256 tokensLength = whitelistedTokensArr.length; 
        for(uint i = 0; i < tokensLength; i++){
            if( whitelistedTokensArr[i] == _token ){
                whitelistedTokensArr[i] = whitelistedTokensArr[tokensLength - 1];
                whitelistedTokensArr.pop();
                emit DelistToken(_token);
                return true;
            }
        }
        return false;
    }


    function getMinTokensAmountForETH(
        address _token,
        uint256 _requiredETH
    ) external view override returns (uint256 tokenAmountIn) {

        uint24 fee = _getPoolFee(_token);
        tokenAmountIn = _getMinTokensAmount(address(WETH), _token, _requiredETH, fee);
    }

    function _getMinTokensAmount(
        address _token0,
        address _token1,
        uint256 _amount0,
        uint24 _fee
    ) internal view returns (uint256 _amount1) {
        address pool = uniswapV3Factory.getPool(_token0, _token1, _fee);
        require(
            pool != address(0),
            "PureFiUniswapV3Plugin : Pool does not exist"
        );

        // get current tokens ratio

        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        if (_token0 < _token1) {
            //  ratio = _token1 / _token0; => _amount1 = ratio * amount(_token0) => _amount1 = ratio * _amount0
            _amount1 =
                (((_amount0 * sqrtPriceX96) / 2 ** 96) * sqrtPriceX96) /
                2 ** 96;
        } else {
            // ratio = _token0 / _token1; => _token1 = _token0 / ratio; => _amount1 = _amount0 / ratio
            _amount1 =
                (((_amount0 * 2 ** 96) / sqrtPriceX96) * 2 ** 96) /
                sqrtPriceX96;
        }
    }

    function _getPoolFee(address _token) private view returns(uint24 fee){
        return poolFees[_token];
    }


}
