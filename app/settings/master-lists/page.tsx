"use client";
/* eslint-disable @next/next/no-html-link-for-pages */

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseClient } from "@/lib/supabase";

type Category = "employment_type"|"pay_frequency"|"rate_type"|"department"|"position"|"contract_term"|"leave_type";
type Item = {id:string;category:Category;code:string;label:string;description:string|null;numeric_value:number|null;is_default:boolean;is_active:boolean;is_system:boolean;sort_order:number};
const categories:{code:Category;label:string;help:string}[]=[
  {code:"employment_type",label:"Employment classifications",help:"Regular, probationary, fixed-term, and company classifications"},
  {code:"pay_frequency",label:"Pay frequencies",help:"Payroll cycle assigned to each employee"},
  {code:"rate_type",label:"Rate bases",help:"Hourly, daily, weekly, or monthly compensation basis"},
  {code:"department",label:"Departments",help:"Organization departments and business units"},
  {code:"position",label:"Positions",help:"Job titles available in employee records"},
  {code:"contract_term",label:"Contract terms",help:"Selectable contract lengths in months"},
  {code:"leave_type",label:"Leave types",help:"Company and statutory leave options"},
];

export default function MasterListsPage(){
  const router=useRouter(),db=useRef<SupabaseClient|null>(null);
  const [org,setOrg]=useState(""),[category,setCategory]=useState<Category>("employment_type"),[items,setItems]=useState<Item[]>([]),[message,setMessage]=useState("");
  const load=useCallback(async(client:SupabaseClient)=>{const {data,error}=await client.from("hr_master_list_items").select("id,category,code,label,description,numeric_value,is_default,is_active,is_system,sort_order").order("category").order("sort_order").order("label");if(error)setMessage(error.message);else setItems((data||[]) as Item[]);},[]);
  useEffect(()=>{const client=createSupabaseClient();db.current=client;client.auth.getUser().then(async({data})=>{if(!data.user)return router.replace("/login");const {data:p}=await client.from("profiles").select("organization_id").eq("id",data.user.id).single();if(!p)return setMessage("HR profile was not found.");setOrg(p.organization_id);await load(client);});},[load,router]);
  async function addItem(e:FormEvent<HTMLFormElement>){e.preventDefault();const el=e.currentTarget,f=new FormData(el),label=String(f.get("label")).trim(),code=String(f.get("code")||label).trim().toLowerCase().replace(/[^a-z0-9]+/g,"_").replace(/^_|_$/g,"");const numeric=String(f.get("numeric_value")||"");const {error}=await db.current!.from("hr_master_list_items").insert({organization_id:org,category,code,label,description:f.get("description")||null,numeric_value:numeric?Number(numeric):null,sort_order:Number(f.get("sort_order"))||100});if(error)return setMessage(error.message);el.reset();setMessage(`${label} added.`);await load(db.current!);}
  async function toggle(item:Item){const {error}=await db.current!.from("hr_master_list_items").update({is_active:!item.is_active,updated_at:new Date().toISOString()}).eq("id",item.id);if(error)return setMessage(error.message);await load(db.current!);}
  async function makeDefault(item:Item){const {error}=await db.current!.rpc("hr_set_master_default",{p_item_id:item.id});if(error)return setMessage(error.message);setMessage(`${item.label} is now the default.`);await load(db.current!);}
  const visible=items.filter(item=>item.category===category), current=categories.find(c=>c.code===category)!;
  return <main className="admin-page"><header className="admin-top"><div className="brand login-brand"><b>P</b> PulseHR</div><div><a href="/">Dashboard</a><a href="/employees">Employees</a><a href="/attendance">Attendance</a></div></header><div className="master-page admin-content">
    <div className="admin-title"><small>HR CONFIGURATION</small><h1>Master lists</h1><p>Manage the options used by employee, leave, attendance, and payroll forms.</p></div>{message&&<div className="login-message">{message}</div>}
    <div className="master-layout"><nav className="master-nav card">{categories.map(c=><button key={c.code} className={category===c.code?"selected":""} onClick={()=>setCategory(c.code)}><b>{c.label}</b><small>{items.filter(i=>i.category===c.code&&i.is_active).length} active</small></button>)}</nav>
      <section><article className="card master-editor"><div><h2>{current.label}</h2><p>{current.help}</p></div><form onSubmit={addItem}><div className="master-form-grid"><label>Display name<input name="label" required placeholder="Enter a new option"/></label><label>Code<input name="code" placeholder="Generated if blank"/></label>{(category==="contract_term"||category==="leave_type")&&<label>Numeric value<input name="numeric_value" type="number" min="0" step="0.5" placeholder={category==="contract_term"?"Months":"Default days"}/></label>}<label>Display order<input name="sort_order" type="number" defaultValue="100"/></label><label className="wide">Description<input name="description"/></label></div><button className="primary">Add to master list</button></form></article>
      <article className="card master-table"><div className="master-row head"><span>Option</span><span>Code / value</span><span>Status</span><span>Default</span><span>Actions</span></div>{visible.map(item=><div className={`master-row ${item.is_active?"":"archived"}`} key={item.id}><span><b>{item.label}</b><small>{item.description|| (item.is_system?"System starter":"Company option")}</small></span><span><code>{item.code}</code>{item.numeric_value!==null&&<small>{item.numeric_value} {category==="contract_term"?"months":"days"}</small>}</span><span><i className={item.is_active?"active":""}>{item.is_active?"Active":"Archived"}</i></span><span>{item.is_default?<b>Default</b>:item.is_active?<button onClick={()=>makeDefault(item)}>Set default</button>:"—"}</span><span><button onClick={()=>toggle(item)}>{item.is_active?"Archive":"Restore"}</button></span></div>)}{visible.length===0&&<p className="master-empty">No options yet. Add the first one above.</p>}</article></section>
    </div></div></main>;
}
