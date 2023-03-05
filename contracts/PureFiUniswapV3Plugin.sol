// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/UniswapV3/IUniswapV3Factory.sol";
import "./interfaces/UniswapV3/IUniswapV3Pool.sol";
import "./interfaces/UniswapV3/ISwapRouter.sol";
import "./interfaces/UniswapV3/IWETH9.sol";

import "./interfaces/IPureFiPlugin.sol";
import "./interfaces/IPaymasterPluginCompatible.sol";


contract PureFiUniswapV3Plugin is AccessControl, IPureFiPlugin {
    uint32 constant DENOM_PERCENTAGE = 10000;

    IUniswapV3Factory uniswapV3Factory;
    ISwapRouter uniswapV3Router;
    address public paymaster;
    IWETH9 WETH;
    uint32 slippage;

    mapping(address => uint24) public poolFees;

    event SetPoolFee( address indexed token, uint24 indexed fee);

    constructor(
        address _admin,
        address _uniswapV3Router,
        address _uniswapV3Factory,
        address _paymaster,
        address _WETH
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        paymaster = _paymaster;
        WETH = IWETH9(_WETH);
        slippage = 30; // 0.3%
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
        return 1000004;
    }

    function swapToken( 
        address _token, 
        uint256 _amount 
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns( uint256 receivedETH ){

        // approve from within paymaster
        require(
            IPaymasterPluginCompatible(paymaster).approveTokenForPlugin(_token, _amount),
            "PureFiUniswapV3Plugin : Approve fail"
        );
        // trasferFrom paymaster

        require(
            IERC20(_token).transferFrom(paymaster, address(this), _amount),
            "PureFiUniswapV3Plugin : TransferFrom fail"
        );

        //swap
        uint24 poolFee = _getPoolFee(_token);
        uint256 maxAmountOut = _getAmountOut(_amount, _token, address(WETH), poolFee);
        uint256 minAmountOut = maxAmountOut * ( DENOM_PERCENTAGE - slippage ) / DENOM_PERCENTAGE;

        receivedETH = _swapToken(_token, _amount, minAmountOut);
    }

    function _swapToken(
        address _token,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOut) {

        require(_amountIn > 0, "PureFiUniswapV3Plugin : Nothing to swap");

        // approve
        require(
            IERC20(_token).approve(address(uniswapV3Router), _amountIn),
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
                amountIn: _amountIn,
                amountOutMinimum: _minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }


    // set pool fee for pair token/WETH
    function setPoolFee( address _token, uint24 _fee ) external onlyRole(DEFAULT_ADMIN_ROLE){

        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(_token, address(WETH), _fee);
        require(pool != address(0), "PureFiUniswapV3Plugin : Pool with this doesn't exist");
        require(_fee > 0, "PureFiUniswapV3Plugin : Incorrect fee value");
        poolFees[_token] = _fee;
    }

    function getMinTokensAmountForETH(
        address _token,
        uint256 _requiredETH
    ) external view override returns (uint256 tokenAmountIn) {

        uint24 fee = _getPoolFee(_token);
        tokenAmountIn = _getAmountIn(_requiredETH, _token, address(WETH), fee);
    }

    // get maximum output amount of tokenOut for _amountIn _tokenIn
    function _getAmountOut( 
        uint256 _amountIn, 
        address _tokenIn, 
        address _tokenOut,
        uint24 _fee
    ) internal view returns (uint256 _amountOut){
        address pool = uniswapV3Factory.getPool(_tokenIn, _tokenOut, _fee);
        require(pool != address(0),"PureFiUniswapV3Plugin : Pool does not exist");
        // get current tokens ratio
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        uint256 amountInWithFee = _amountIn * ( DENOM_PERCENTAGE - _fee ) / DENOM_PERCENTAGE;
        
        if( _tokenIn < _tokenOut){
            //  ratio = _tokenOut / _tokenIn; => _amountOut = ratio * amount(_tokenIn) => _amountOut = ratio * _amountIn
            _amountOut = (((amountInWithFee * sqrtPriceX96) / 2 ** 96) * sqrtPriceX96) / 2 ** 96;
        }else{
            _amountOut = (((amountInWithFee * 2 ** 96) / sqrtPriceX96) * 2 ** 96) / sqrtPriceX96;
        }
    }
    // get minimum amount of _tokenIn for getting _amountOut of _tokenOut
    function _getAmountIn(
        uint256 _amountOut,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee
    ) internal view returns( uint256 _amountIn ){
        address pool = uniswapV3Factory.getPool(_tokenIn, _tokenOut, _fee);
        require(pool != address(0),"PureFiUniswapV3Plugin : Pool does not exist");
        // get current tokens ratio
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        uint256 amountInWithoutFee;
        if( _tokenIn < _tokenOut ){
            // ratio = _tokenOut / _tokenIn; => _tokenIn = _tokenOut / ratio;
            amountInWithoutFee = (((_amountOut * 2**96) / sqrtPriceX96) * 2**96) / sqrtPriceX96;
        }else{
            // ratio = _tokenIn / _tokenOut; => _tokenIn = ratio * _tokenOut;
            amountInWithoutFee = (((_amountOut * sqrtPriceX96) / 2**96) * sqrtPriceX96) / 2**96;
        }
        // add extra amount for fee compensation;
        _amountIn = amountInWithoutFee * DENOM_PERCENTAGE / ( DENOM_PERCENTAGE - _fee );

    }

    function _getPoolFee(address _token) private view returns(uint24 fee){
        return poolFees[_token];
    }

    function withdrawETH( uint256 _amount, address _recipient ) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_recipient != address(0), "PureFiUniswapV3Plugin : Incorect recipient address");

        uint256 wethBalance = WETH.balanceOf(address(this));
        require(wethBalance >= _amount, "PureFiUniswapV3Plugin : Amount too high");

        _wethWithdraw(_amount);

        (bool sent, ) = payable(_recipient).call{value : _amount}("");
        require(sent, "PureFiUniswapV3Plugin : Failed to send Ether");
    }

    // convert ERC20 WETH to native eth
    function _wethWithdraw( uint256 _amount) internal{
        WETH.withdraw(_amount);
    }

    function refundPaymaster( uint256 _amount ) external onlyRole(DEFAULT_ADMIN_ROLE){
        uint256 wethBalance = WETH.balanceOf(address(this));
        require(wethBalance >= _amount, "PureFiUniswapV3Plugin : Insufficient funds");

        _wethWithdraw(_amount);

        (bool sent, ) = payable(paymaster).call{value : _amount}("");
        require(sent, "PureFiUniswapV3Plugin : Failed to send Ether");
    }

    function setSlippage( uint32 _slippage ) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_slippage > 0, "PureFiUniswapV3Plugin : Incorrect slippage");
        slippage = _slippage;
    }
}
