{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Plutarch.Api.V1.Crypto (
  PPubKeyHash (PPubKeyHash),
  PubKey (PubKey, getPubKey),
  pubKeyHash,
) where

import qualified PlutusLedgerApi.V1 as Plutus

import Data.Coerce (coerce)
import Plutarch.Api.Internal.Hashing (hashLedgerBytes)
import Plutarch.Builtin (Flip)
import Plutarch.Lift (
  DerivePConstantViaBuiltin (DerivePConstantViaBuiltin),
  PConstantDecl,
  PLifted,
  PUnsafeLiftDecl,
 )
import Plutarch.Prelude
import Plutarch.TryFrom (PTryFrom (PTryFromExcess, ptryFrom'))
import Plutarch.Unsafe (punsafeCoerce)

newtype PPubKeyHash (s :: S) = PPubKeyHash (Term s PByteString)
  deriving stock (Generic)
  deriving anyclass (PlutusType, PIsData, PEq, PPartialOrd, POrd)
instance DerivePlutusType PPubKeyHash where type DPTStrat _ = PlutusTypeNewtype

instance PUnsafeLiftDecl PPubKeyHash where type PLifted PPubKeyHash = Plutus.PubKeyHash
deriving via
  (DerivePConstantViaBuiltin Plutus.PubKeyHash PPubKeyHash PByteString)
  instance
    PConstantDecl Plutus.PubKeyHash

instance PTryFrom PData (PAsData PPubKeyHash) where
  type PTryFromExcess PData (PAsData PPubKeyHash) = Flip Term PPubKeyHash
  ptryFrom' opq = runTermCont $ do
    unwrapped <- tcont . plet $ ptryFrom @(PAsData PByteString) opq snd
    tcont $ \f ->
      pif (plengthBS # unwrapped #== 28) (f ()) (ptraceError "ptryFrom(PPubKeyHash): must be 28 bytes long")
    pure (punsafeCoerce opq, pcon . PPubKeyHash $ unwrapped)

newtype PubKey = PubKey {getPubKey :: Plutus.LedgerBytes}
  deriving stock (Eq, Ord, Show)

pubKeyHash :: PubKey -> Plutus.PubKeyHash
pubKeyHash = coerce hashLedgerBytes
