# Focused coin validation fix

Exact known failure: canonical_wallet/valid rejects wallet_ledger.coins unless it is a finite integral number between0 and2,000,000,000. The B020:COINS log alone cannot distinguish missing/null/string/negative/fractional/over-limit. No specific subtype is claimed without the new diagnostics.

Trace: SaveService wallet.coins → CloudSaveService snapshot copies the same value to profile.coins and meta/main.wallet_ledger.coins → FirestoreCodec encodes integer/integral float as integerValue, decodes integerValue to int and doubleValue to float → RemoteEdit canonical_wallet validates before mirror resolution. Missing map fields remain missing; null and string types remain unchanged. Integral floats already pass.

Changed implementation: Account/RemoteEdit.gd only. Added source/presence/type/numeric/integral/range diagnostics for root and wallet_ledger without values. Missing wallet coins can be reconstructed only from valid existing root coins when both server document versions are usable and root updateTime>=wallet updateTime. A missing key has no competing supplied value; malformed supplied values are never substituted. Missing required documents, null/string/fractional/negative/over-limit values and unproven/ambiguous mirrors still fail. Existing mirror resolution/conflict checks continue afterward. No balances are summed and no currency grant occurs.

Static trace: normal AccountA numeric wallet passes unchanged; historical missing redundant wallet key with authoritative root evidence canonicalizes; supplied invalid wallet coins reject; old/equal divergent supplied numeric mirrors still use established mirror policy; UID, save, polling, provider and native code are unchanged. Modified script parsed with gdtoolkit; ZIP bytes/integrity checked. No runtime tests.

Schema5 and all save/progress/purchase data preserved. Kotlin/native unchanged; AAR rebuild NOT required. android/build and RushFirebaseBridge.aar are excluded. Actual AccountB subtype remains unknown until WALLET_COINS_* diagnostics are captured; send those marker lines only, not a payload.
