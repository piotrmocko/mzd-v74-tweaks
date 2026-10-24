// Execute the actual inserted boundary checks, not a second implementation.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'../../list-loop.sh'),'utf8');
const groups={};
for(const line of source.split('\n')){
  const m=line.match(/^    block\[(\d+),1,(\d+)\] = (.*)$/);
  if(m){(groups[m[1]]||(groups[m[1]]=[]))[Number(m[2])-1]=JSON.parse(m[3]);}
}
let checks=0,handlers=0;
for(const rows of Object.values(groups)){
  const block=rows.join('\n'),start=block.indexOf('if (this._getFocussedIndex() == currentFocussedIndex)');
  if(start<0)continue;
  let first=block.indexOf('{',start),depth=1,end=first+1;
  for(;depth;end++){if(block[end]==='{')depth++;if(block[end]==='}')depth--;assert(end<block.length);}
  const fn=new Function('currentFocussedIndex',block.slice(start,end));
  const down=block.includes('currentFocussedIndex + 1');handlers++;
  function check(current,disabled,missing,expected,moved=false){
    const items=Array.from({length:20},(_,i)=>missing.includes(i)?undefined:{disabled:disabled.includes(i)}),actual=[];
    const context={dataList:{itemCount:20,items},_getFocussedIndex:()=>current+(moved?1:0),_manageFocus:i=>actual.push(i)};
    const result=fn.call(context,current);
    assert.deepEqual(actual,expected===null?[]:[expected],JSON.stringify({down,current,disabled,missing,expected}));
    assert.equal(result,expected===null?undefined:'consumed');checks++;
  }
  // Normal scroll threshold: unchanged focus must fall through to OEM scrolling.
  check(down?6:1,[],[],null);
  check(down?19:0,[],[],down?0:19);
  // Skip disabled entries at both the departure and destination boundaries.
  check(down?18:1,down?[19]:[0],[],down?0:19);
  check(down?19:0,down?[0,1]:[19,18],[],down?2:17);
  check(down?6:5,down?[7,8,9]:[4,3,2],[],null);
  // Missing data must not be mistaken for the absence of a selectable item.
  check(down?6:5,down?[7]:[4],down?[8]:[3],null);
  check(down?19:0,[],down?[0]:[19],null);
  check(down?19:0,Array.from({length:20},(_,i)=>i),[],null);
  check(down?19:0,[],[],null,true);
}
assert.equal(handlers,4);
console.log('Passed '+checks+' list-loop boundary/disabled-item/missing-data regressions across four handlers.');
