/* Presentation only. The native locale and the shared resource table arrive
   before document creation; no network, reload, photo write or render is needed. */
(() => {
  'use strict';
  const configuration = window.grainagentLanguage || {language:'en',messages:{}};
  window.grainagentLanguage = configuration;
  const messages = configuration.messages;
  const sources = new WeakMap();
  const attributes = new WeakMap();
  let language = configuration.language;
  const translatedKeys = new Map();
  for (const [key,row] of Object.entries(messages)) {
    if(key.includes("␟"))continue; // Native-only contextual variants are never DOM source labels.
    for (const code of ['en','fr','es']) if (row[code]) translatedKeys.set(code+'\0'+row[code],key);
  }
  function translate(key, args=[]) {
    const row=messages[key];
    const template=language==='zh-Hans'?key:(row?.[language] ?? row?.en ?? key);
    return template.replace(/\{(\d+)\}/g,(marker,index)=>args[index]===undefined?marker:String(args[index]));
  }
  window.GrainAgentI18n={translate,get language(){return language}};
  const excluded=element=>!element||element.closest('script,style,input,textarea,[contenteditable=true],[data-file-name],[data-photo-id] strong');
  function sourceFor(value, previous, oldLanguage) {
    if(previous?.output===value)return previous.source;
    if(messages[value])return value;
    return translatedKeys.get((oldLanguage||language)+'\0'+value)||value;
  }
  function text(node, oldLanguage) {
    if(excluded(node.parentElement))return;
    const value=node.nodeValue, trimmed=value.trim(); if(!trimmed)return;
    const source=sourceFor(trimmed,sources.get(node),oldLanguage);
    if(!messages[source])return;
    const output=translate(source);
    sources.set(node,{source,output});
    if(output!==trimmed)node.nodeValue=value.slice(0,value.indexOf(trimmed))+output+value.slice(value.indexOf(trimmed)+trimmed.length);
  }
  const names=['aria-label','aria-valuetext','title','placeholder','alt','data-tooltip'];
  function element(el,oldLanguage) {
    if(!el||el.closest('script,style,[data-file-name],[data-photo-id] strong'))return;
    const record=attributes.get(el)||{};
    for(const name of names){
      const value=el.getAttribute(name);if(!value)continue;
      const source=sourceFor(value,record[name],oldLanguage);if(!messages[source])continue;
      const output=translate(source);record[name]={source,output};
      if(output!==value)el.setAttribute(name,output);
    }
    attributes.set(el,record);
  }
  function tree(root,oldLanguage) {
    if(root.nodeType===Node.TEXT_NODE){text(root,oldLanguage);return;}
    if(root.nodeType!==Node.ELEMENT_NODE&&root!==document)return;
    if(root.nodeType===Node.ELEMENT_NODE){element(root,oldLanguage);}
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT|NodeFilter.SHOW_TEXT);
    while(walker.nextNode()){
      const node=walker.currentNode;
      if(node.nodeType===Node.TEXT_NODE)text(node,oldLanguage);else element(node,oldLanguage);
    }
  }
  const observer=new MutationObserver(records=>{
    observer.disconnect();
    for(const record of records){
      if(record.type==='characterData')text(record.target);
      else if(record.type==='attributes')element(record.target);
      else for(const node of record.addedNodes)tree(node);
    }
    observe();
  });
  function observe(){observer.observe(document.documentElement,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:names});}
  function apply(oldLanguage){
    observer.disconnect();
    document.documentElement.lang=language;
    tree(document,oldLanguage);
    observe();
  }
  window.addEventListener('grainagent:language',event=>{
    const next=event.detail.language;if(next===language)return;
    const old=language;language=next;configuration.language=next;apply(old);
  });
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>apply());else apply();
})();
