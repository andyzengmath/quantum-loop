# Module: Step 4C — Promote Discovered Contracts

**Activation:** runs after Step 4B passes (always-on; no-op when `execution.discoveredContracts` is empty).

After Step 4B passes and before generating observations, promote runtime-discovered contracts to permanent status so that future executions benefit from them.

1. **Read discovered contracts:** Read `execution.discoveredContracts` from quantum.json. If the field is absent or empty, log `[CONTRACTS] No discovered contracts to promote` and skip to Step 5.

2. **Filter for consolidated entries only:** For each entry in `discoveredContracts`, check the `consolidated` field:
   - If `consolidated: true` — this is a verified duplicate that was successfully consolidated by the type-auditor agent. Promote it.
   - If `consolidated: false` — this is a false positive (same name, different concept). Do NOT promote it. Skip silently.

3. **Promote to permanent contracts:** For each `consolidated: true` entry, add a new entry to `contracts.shared_types`:
   - `value`: the type name (the key from `discoveredContracts`)
   - `definitionFile`: taken from the entry's `consolidatedFile` field
   - `consumers`: derived from the entry's `sourceFiles` context (the files that contained duplicate definitions indicate which stories consume the type)
   - Do NOT duplicate — if `contracts.shared_types` already has an entry with the same `value`, update it rather than adding a duplicate

4. **Write to quantum.json:** The promotion is a quantum.json write, not a separate commit. It is included in the observations commit (Step 5). Use the standard atomic write pattern:
   ```bash
   python -c "
   import json
   from datetime import datetime, timezone
   data = json.load(open('quantum.json'))
   discovered = data.get('execution', {}).get('discoveredContracts', {})
   promoted = []
   for name, entry in discovered.items():
       if entry.get('consolidated', False):
           new_contract = {
               'value': name,
               'definitionFile': entry.get('consolidatedFile', ''),
               'consumers': entry.get('sourceFiles', [])
           }
           # Update existing or insert (shared_types is a dict keyed by type name)
           data.setdefault('contracts', {}).setdefault('shared_types', {})[name] = new_contract
           promoted.append(name)
   data['updatedAt'] = datetime.now(timezone.utc).isoformat()
   json.dump(data, open('quantum.json', 'w'), indent=2)
   print(f'[CONTRACTS] Promoted {len(promoted)} discovered types to permanent contracts: {", ".join(promoted)}')
   "
   ```

5. **Log the result:**
   - If types were promoted: `[CONTRACTS] Promoted N discovered types to permanent contracts: TypeA, TypeB, ...`
   - If no discovered contracts (or none with `consolidated: true`): `[CONTRACTS] No discovered contracts to promote`
