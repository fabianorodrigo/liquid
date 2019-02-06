pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-eth/contracts/ownership/Ownable.sol";
import "openzeppelin-eth/contracts/math/SafeMath.sol";
import "zos-lib/contracts/Initializable.sol";

contract CurveEvents {
    event Bought(address indexed buyer, uint256 amount, uint256 paid);
    event Contributed(address indexed buyer, uint256 contribution);
    event Sold(address indexed seller, uint256 amount, uint256 reserveReturned);
}

contract DoubleCurveToken is Initializable, CurveEvents, ERC20, ERC20Detailed {
    using SafeMath for uint256;

    function () payable { revert("Fallback disabled"); }

    address reserveAsset;
    uint256 reserve;    // Amount held in contract to collaterize sells.

    address beneficiary;
    uint256 contributions;

    uint256 slopeN;
    uint256 slopeD;
    uint256 exponent;
    uint256 spreadN;    // Spread is actually only the area under the sell curve
    uint256 spreadD;    //  represented as a fraction of the whole.

    // uint256 preMint;    // Pre-mint is used to start the token price at the desired point.

    function initialize(
        address _reserveAsset,
        address _beneficiary,
        uint256 _slopeN,
        uint256 _slopeD,
        uint256 _exponent,
        uint256 _spreadN,
        uint256 _spreadD,
        uint256 _preMint,
        string _name,
        string _symbol
    )   public
        initializer
    {
        ERC20Detailed.initialize(_name, _symbol, 18);
        _mint(address(0x1337), _preMint);

        reserveAsset = _reserveAsset;
        beneficiary = _beneficiary;
        slopeN = _slopeN;
        slopeD = _slopeD;
        exponent = _exponent;
        spreadN = _spreadN;
        spreadD = _spreadD;
    }

    function withdraw() public returns (bool) {
        require(contributions > 0, "Cannot withdraw 0 amount");
        if (reserveAsset == address(0x0)) {
            beneficiary.transfer(contributions);
        } else {
            ERC20(reserveAsset).transfer(beneficiary, contributions);
        }
        delete contributions;
        return true;
    }

    function buy(uint256 _tokens, uint256 _maxSpend)
        public payable returns (bool)
    {
        uint256 cost = priceToBuy(_tokens);
        // 
        require(
            cost <= _maxSpend
        );
        //
        uint256 reserveAmount = amountToReserve(_tokens);
        contributions = contributions.add(cost.sub(reserveAmount));
        reserve = reserve.add(reserveAmount);

        // If Ether is the reserve send back the extra
        if (reserveAsset == address(0x0)) {
            if (msg.value > cost) {
                msg.sender.transfer(msg.value.sub(cost));
            }
        } else {
            // Otherwise try token transfer
            ERC20(reserveAsset).transferFrom(msg.sender, address(this), cost);
        }

        _mint(msg.sender, _tokens);

        emit Contributed(msg.sender, cost.sub(reserveAmount));
        emit Bought(msg.sender, _tokens, cost);
    }

    function sell(uint256 _tokens, uint256 _minReturn)
        public returns (bool)
    {
        require(
            balanceOf(msg.sender) >= _tokens
        );
        //
        uint256 amountReturned = returnForSell(_tokens);
        //
        require(
            amountReturned >= _minReturn
        );
        //
        reserve = reserve.sub(amountReturned);
        if (reserveAsset == address(0x0)) {
            msg.sender.transfer(amountReturned);
        } else {
            ERC20(reserveAsset).transfer(msg.sender, amountReturned);
        }

        _burn(msg.sender, _tokens);

        emit Sold(msg.sender, _tokens, amountReturned);
    }

    function curveIntegral(uint256 _toX)
        internal view returns (uint256)
    {
        uint256 nexp = exponent.add(1);

        return slopeN.mul(_toX ** nexp).div(nexp).div(slopeD);
    }

    function solveForY(uint256 _X)
        internal view returns (uint256)
    {
        return slopeN.mul(_X ** exponent).div(slopeN);
    }

    function priceToBuy(uint256 _tokens)
        public view returns (uint256)
    {
        return curveIntegral(totalSupply().add(_tokens)).sub(curveIntegral(totalSupply()));
    }

    function returnForSell(uint256 _tokens)
        public view returns (uint256)
    {
        return reserve.sub(
            spreadN.mul(
                curveIntegral(totalSupply().sub(_tokens))
            ).div(spreadD)
        );
    }

    function amountToReserve(uint256 _tokens)
        public view returns (uint256)
    {
        return spreadN.mul(
            curveIntegral(totalSupply().add(_tokens))
        ).div(spreadD).sub(reserve);
    }

    function currentPrice()
        public view returns (uint256)
    {
        return solveForY(totalSupply());
    }

    function marketCap()
        public view returns (uint256)
    {
        return currentPrice().mul(totalSupply());
    }
}