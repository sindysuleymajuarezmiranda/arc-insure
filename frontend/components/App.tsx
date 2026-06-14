"use client";
import { useEffect, useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther, formatEther, isAddress } from "viem";
import { Shell22, Brand } from "./shells";
import { DefiPanel } from "./DefiPanel";
const CONTRACT = (process.env.NEXT_PUBLIC_CONTRACT_ADDRESS || "0x0") as `0x${string}`;
const abi = [
  { name: "buy", type: "function", stateMutability: "payable", inputs: [{ name: "coverage", type: "uint256" }], outputs: [{ type: "uint256" }] },,  { name: "fileClaim", type: "function", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }], outputs: [] },,  { name: "resolve", type: "function", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }, { name: "payOut", type: "bool" }], outputs: [] },,  { name: "fundPool", type: "function", stateMutability: "payable", inputs: [], outputs: [] },,  { name: "pool", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },,  { name: "owner", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },,  { name: "get", type: "function", stateMutability: "view", inputs: [{ name: "id", type: "uint256" }], outputs: [{ type: "tuple", components: [{ name: "holder", type: "address" }, { name: "premium", type: "uint256" }, { name: "coverage", type: "uint256" }, { name: "status", type: "uint8" }] }] },,  { name: "total", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;
const cut = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const fmtUsd = (w?: bigint) => w === undefined ? "0.00" : Number(formatEther(w)).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const brand: Brand = { name: "Arc Insure", sub: "On-chain insurance", emoji: "🛡️", color: "fuchsia", font: '"Trebuchet MS","Segoe UI",sans-serif', shape: "rounded-full", hero: "Parametric cover", herosub: "A built-in DeFi pool, right inside." };
function Tile({ id, me, pending, send }: { id: bigint; me?: string; pending: boolean; send: (fn: string, args: any[], v?: bigint) => void }) {
  const { data: it } = useReadContract({ address: CONTRACT, abi, functionName: "get", args: [id] });
  const [amt, setAmt] = useState("");
  if (!it) return null;
  const done = false;
  return (
    <div className="bg-[var(--card)] border border-[color:var(--cardb)] rounded-[var(--rad)] p-4 space-y-2 hover:border-fuchsia-500/40 transition-colors">
      <div className="flex items-center gap-3"><div className="w-10 h-10 rounded-full bg-fuchsia-500/15 grid place-items-center text-lg shrink-0">🛡️</div>
        <div className="flex-1 min-w-0"><div className="font-bold text-[color:var(--txt)]">${fmtUsd(it.coverage)}</div><div className="text-[11px] text-[color:var(--mut)] truncate">{`#${id}`}</div></div>
        <span className="text-[11px] bg-[var(--ipt)] px-2 py-1 rounded-full shrink-0">{done ? "Done ✓" : "Open"}</span></div>
      {!done && <div className="flex flex-wrap items-center gap-2"><button onClick={()=>send("fileClaim",[id])} disabled={pending} className="px-2.5 py-1.5 bg-[var(--btn2)] text-[color:var(--txt)] rounded-lg hover:bg-gray-600 disabled:opacity-40 text-xs">{pending?"…":"File claim"}</button></div>}
    </div>
  );
}
export default function App() {
  const { address, isConnected } = useAccount();
  const [tab, setTab] = useState("home");
  const [f, setF] = useState<any>({coverage:"",amt:""});
  const { data: count } = useReadContract({ address: CONTRACT, abi, functionName: "total" });
  const { writeContract, data: tx, isPending, reset } = useWriteContract();
  const { isSuccess, isLoading: cfm } = useWaitForTransactionReceipt({ hash: tx, query: { enabled: !!tx } });
  useEffect(() => { if (isSuccess) { reset(); setF({coverage:"",amt:""}); } }, [isSuccess]); // eslint-disable-line
  const pending = isPending || cfm;
  const n = count !== undefined ? Number(count) : 0;
  const send = (fn: string, args: any[], v?: bigint) => writeContract({ address: CONTRACT, abi, functionName: fn as any, args, value: v });
  return (<Shell22 brand={brand} tabs={[["home", "Policies"], ["pool", "Depth"], ["swap", "Trade"]]} tab={tab} setTab={setTab}>
    {tab === "home" && <div className="space-y-4">
      <div className="bg-[var(--card)] border border-[color:var(--cardb)] rounded-[var(--rad)] p-6 space-y-3">
        <input value={f.coverage} onChange={e=>setF(v=>({...v,coverage:e.target.value}))} placeholder="Coverage" type="number" className="w-full bg-[var(--ipt)] border border-[color:var(--iptb)] rounded-[var(--rad)] px-4 py-2.5 text-sm focus:outline-none focus:border-fuchsia-500" />
        <div className="relative"><span className="absolute left-3 top-1/2 -translate-y-1/2 text-[color:var(--mut)]">$</span><input value={f.amt} onChange={e=>setF(v=>({...v,amt:e.target.value}))} type="number" placeholder="USDC amount" className="w-full bg-[var(--ipt)] border border-[color:var(--iptb)] rounded-[var(--rad)] pl-7 pr-3 py-2.5 text-sm focus:outline-none" /></div>
        <button onClick={() => send("buy", [parseEther(f.coverage||"0")], parseEther(f.amt||"0"))} disabled={!isConnected || pending || (!(Number(f.amt)>0))} className="w-full py-3 font-bold rounded-xl bg-gradient-to-r from-fuchsia-500 to-fuchsia-600 text-white hover:opacity-90 disabled:opacity-40">{pending ? "…" : "Buy policie 🛡️"}</button>
      </div>
      {n > 0 ? <div className="space-y-3">{Array.from({ length: n }, (_, i) => BigInt(n - 1 - i)).map(id => <Tile key={id.toString()} id={id} me={address} pending={pending} send={send} />)}</div> : <div className="text-center text-sm text-[color:var(--mut)] py-8">Nothing yet 🛡️</div>}
    </div>}
    {tab === "pool" && <DefiPanel color="fuchsia" show={["pool"]} note="Liquidity pool + yield, 0.3% fee, no middlemen · Arc." />}
    {tab === "swap" && <DefiPanel color="fuchsia" show={["swap"]} note="Liquidity pool + yield, 0.3% fee, no middlemen · Arc." />}
  </Shell22>);
}