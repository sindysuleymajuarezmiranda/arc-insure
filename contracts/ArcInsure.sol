// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address from, address to, uint256 a) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}

/// @title ArcDefi — reusable AMM (swap + liquidity) + yield vault module.
/// USDC is the native gas token (msg.value, 18 dec); EURC is an ERC20 (6 dec).
contract ArcDefi {
    IERC20 public eurc;
    address public dfOwner;
    uint256 public resUsdc;
    uint256 public resEurc;
    uint256 public totalLp;
    mapping(address => uint256) public lpOf;
    uint16 public constant FEE_BPS = 30;

    uint256 public earnApyBps = 800;
    struct EPos { uint256 principal; uint256 since; uint256 accrued; }
    mapping(address => EPos) private earnPos;
    uint256 public earnTotal;

    event Swapped(address indexed u, bool usdcToEurc, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed u, uint256 usdc, uint256 eurc, uint256 lp);
    event LiquidityRemoved(address indexed u, uint256 usdc, uint256 eurc, uint256 lp);
    event EarnDeposited(address indexed u, uint256 amount);
    event EarnWithdrawn(address indexed u, uint256 principal, uint256 interest);

    constructor(address _eurc) { eurc = IERC20(_eurc); dfOwner = msg.sender; }

    function _sqrt(uint256 x) private pure returns (uint256 y) { if (x == 0) return 0; uint256 z = (x + 1) / 2; y = x; while (z < y) { y = z; z = (x / z + z) / 2; } }

    function addLiquidity(uint256 eurcAmt) external payable returns (uint256 lp) {
        require(msg.value > 0 && eurcAmt > 0, "zero");
        require(eurc.transferFrom(msg.sender, address(this), eurcAmt), "eurc in");
        if (totalLp == 0) { lp = _sqrt(msg.value * eurcAmt); }
        else { uint256 a = msg.value * totalLp / resUsdc; uint256 b = eurcAmt * totalLp / resEurc; lp = a < b ? a : b; }
        require(lp > 0, "lp 0");
        resUsdc += msg.value; resEurc += eurcAmt; totalLp += lp; lpOf[msg.sender] += lp;
        emit LiquidityAdded(msg.sender, msg.value, eurcAmt, lp);
    }
    function removeLiquidity(uint256 lp) external {
        require(lp > 0 && lpOf[msg.sender] >= lp, "lp");
        uint256 u = lp * resUsdc / totalLp; uint256 e = lp * resEurc / totalLp;
        lpOf[msg.sender] -= lp; totalLp -= lp; resUsdc -= u; resEurc -= e;
        require(eurc.transfer(msg.sender, e), "eurc out");
        (bool ok,) = payable(msg.sender).call{value: u}(""); require(ok, "usdc out");
        emit LiquidityRemoved(msg.sender, u, e, lp);
    }
    function _out(uint256 amountIn, uint256 rIn, uint256 rOut) private pure returns (uint256) {
        uint256 f = amountIn * (10000 - FEE_BPS) / 10000; return f * rOut / (rIn + f);
    }
    function swapUsdcToEurc(uint256 minOut) external payable returns (uint256 outAmt) {
        require(msg.value > 0 && resEurc > 0, "liq");
        outAmt = _out(msg.value, resUsdc, resEurc);
        require(outAmt >= minOut && outAmt < resEurc, "slippage");
        resUsdc += msg.value; resEurc -= outAmt;
        require(eurc.transfer(msg.sender, outAmt), "eurc out");
        emit Swapped(msg.sender, true, msg.value, outAmt);
    }
    function swapEurcToUsdc(uint256 amountIn, uint256 minOut) external returns (uint256 outAmt) {
        require(amountIn > 0 && resUsdc > 0, "liq");
        require(eurc.transferFrom(msg.sender, address(this), amountIn), "eurc in");
        outAmt = _out(amountIn, resEurc, resUsdc);
        require(outAmt >= minOut && outAmt < resUsdc, "slippage");
        resEurc += amountIn; resUsdc -= outAmt;
        (bool ok,) = payable(msg.sender).call{value: outAmt}(""); require(ok, "usdc out");
        emit Swapped(msg.sender, false, amountIn, outAmt);
    }
    function quote(bool usdcToEurc, uint256 amountIn) external view returns (uint256) {
        if (amountIn == 0) return 0;
        return usdcToEurc ? _out(amountIn, resUsdc, resEurc) : _out(amountIn, resEurc, resUsdc);
    }
    function reserves() external view returns (uint256 usdc, uint256 eurcBal, uint256 lp) { return (resUsdc, resEurc, totalLp); }

    function _earnPending(EPos memory p) private view returns (uint256) {
        if (p.principal == 0) return 0;
        return p.principal * earnApyBps * (block.timestamp - p.since) / (10000 * 365 days);
    }
    function earnPending(address u) public view returns (uint256) { EPos memory p = earnPos[u]; return p.accrued + _earnPending(p); }
    function earnPrincipal(address u) external view returns (uint256) { return earnPos[u].principal; }
    function earnBalanceOf(address u) external view returns (uint256) { return earnPos[u].principal + earnPending(u); }
    function earnDeposit() external payable {
        require(msg.value > 0, "0");
        EPos storage p = earnPos[msg.sender];
        p.accrued += _earnPending(p); p.principal += msg.value; p.since = block.timestamp; earnTotal += msg.value;
        emit EarnDeposited(msg.sender, msg.value);
    }
    function earnWithdraw() external {
        EPos storage p = earnPos[msg.sender];
        uint256 principal = p.principal; require(principal > 0, "none");
        uint256 interest = p.accrued + _earnPending(p); uint256 payout = principal + interest;
        require(address(this).balance >= payout, "reserve");
        earnTotal -= principal; p.principal = 0; p.accrued = 0; p.since = block.timestamp;
        (bool ok,) = payable(msg.sender).call{value: payout}(""); require(ok, "pay");
        emit EarnWithdrawn(msg.sender, principal, interest);
    }
    function setEarnApy(uint256 bps) external { require(msg.sender == dfOwner && bps <= 5000, "no"); earnApyBps = bps; }
    function earnFund() external payable { require(msg.sender == dfOwner, "no"); }
    receive() external payable {}
}

contract ArcInsure is ArcDefi {
    address public owner;
    uint256 public pool;
    struct Policy { address holder; uint256 premium; uint256 coverage; uint8 status; } // 0 active 1 claimed-pending 2 paid 3 rejected
    Policy[] public policies;
    mapping(address => uint256[]) private mineMap;
    constructor(address _eurc) ArcDefi(_eurc) { owner = msg.sender; }
    event Bought(uint256 indexed id, address indexed holder, uint256 coverage);
    event Filed(uint256 indexed id);
    event Resolved(uint256 indexed id, bool paid);
    function buy(uint256 coverage) external payable returns (uint256 id) {
        require(msg.value > 0 && coverage > 0, "bad");
        pool += msg.value;
        id = policies.length; policies.push(Policy(msg.sender, msg.value, coverage, 0));
        mineMap[msg.sender].push(id); emit Bought(id, msg.sender, coverage);
    }
    function fileClaim(uint256 id) external {
        Policy storage p = policies[id];
        require(msg.sender == p.holder && p.status == 0, "no");
        p.status = 1; emit Filed(id);
    }
    function resolve(uint256 id, bool payOut) external {
        require(msg.sender == owner, "not owner");
        Policy storage p = policies[id]; require(p.status == 1, "not pending");
        if (payOut) {
            require(pool >= p.coverage, "pool low");
            pool -= p.coverage; p.status = 2;
            (bool ok,) = payable(p.holder).call{value: p.coverage}(""); require(ok, "fail");
        } else { p.status = 3; }
        emit Resolved(id, payOut);
    }
    function fundPool() external payable { pool += msg.value; }
    function get(uint256 id) external view returns (Policy memory) { return policies[id]; }
    function getMine(address u) external view returns (uint256[] memory) { return mineMap[u]; }
    function total() external view returns (uint256) { return policies.length; }
}
