{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DefaultSignatures #-}

module Plutarch.Show (
  PShow (pshow'),
  pshow,
) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.List.NonEmpty as NE
import Data.Semigroup (sconcat)
import Data.String (IsString (fromString))
import qualified Data.Text as T
import Generics.SOP (
  All,
  All2,
  ConstructorName,
  HasDatatypeInfo,
  K (K),
  NP,
  NS,
  Proxy (Proxy),
  SOP (SOP),
  constructorInfo,
  constructorName,
  datatypeInfo,
  hcmap,
  hcollapse,
  hindex,
  hmap,
 )
import Plutarch.Bool (PBool, PEq ((#==)), POrd ((#<)), pif)
import Plutarch.Integer (PInteger, PIntegral (pquot, prem))
import Plutarch.Internal (punsafeAsClosedTerm)
import Plutarch.Internal.Generic (PCode, PGeneric, pfrom)
import Plutarch.Internal.Other (
  PlutusType,
  Term,
  perror,
  pfix,
  phoistAcyclic,
  plam,
  plet,
  pmatch,
  (#),
  (#$),
  type (:-->),
 )
import Plutarch.Lift (pconstant)
import Plutarch.String (PString)

class PShow t where
  -- | Return the string representation of a Plutarch value
  --
  --  If the wrap argument is True, optionally wrap the output in `(..)` if it
  --  represents multiple parameters.
  pshow' :: Bool -> Term s t -> Term s PString
  default pshow' :: (PGeneric s t, PlutusType t, HasDatatypeInfo (t s), All2 PShow (PCode s t)) => Bool -> Term s t -> Term s PString
  pshow' wrap x = gpshow wrap # x

-- | Return the string representation of a Plutarch value
pshow :: PShow a => Term s a -> Term s PString
pshow = pshow' False

instance PShow PString where
  -- FIXME: We ideally want to wrap the string in quotes, and escape it
  -- appropriately just like Haskell's Show instance. However, there appears to
  -- be no way to do this using Plutus' builtins. So we will just return the
  -- string as is.
  pshow' _ = id

instance PShow PBool where
  pshow' _ x = pmatch x (pconstant @PString . T.pack . show)

instance PShow PInteger where
  pshow' _ x = pshowInt # x
    where
      pshowInt = phoistAcyclic $
        pfix #$ plam $ \self n ->
          let sign = pif (n #< 0) "-" ""
           in sign
                <> ( plet (pquot # abs n # 10) $ \q ->
                      plet (prem # abs n # 10) $ \r ->
                        pif
                          (q #== 0)
                          (pshowDigit # r)
                          ( plet (self # q) $ \prefix ->
                              prefix <> pshowDigit # r
                          )
                   )
      pshowDigit :: Term s (PInteger :--> PString)
      pshowDigit = phoistAcyclic $
        plam $ \digit ->
          pcase perror digit $
            flip fmap [0 .. 9] $ \(x :: Integer) ->
              (pconstant x, pconstant (T.pack . show $ x))
      pcase :: PEq a => Term s b -> Term s a -> [(Term s a, Term s b)] -> Term s b
      pcase otherwise x = \case
        [] -> otherwise
        ((x', r) : cs) -> pif (x #== x') r $ pcase otherwise x cs

-- | Generic version of `pshow`
gpshow ::
  forall a s.
  (PGeneric s a, HasDatatypeInfo (a s), PlutusType a, All2 PShow (PCode s a)) =>
  Bool ->
  Term s (a :--> PString)
gpshow wrap =
  phoistAcyclic $
    punsafeAsClosedTerm @s $
      plam $ \x ->
        pmatch x $ \x' ->
          productGroup wrap " " $ gpshow' @a (pfrom x')

-- | Like `gpshow`, but returns the individual parameters list
gpshow' ::
  forall a s.
  (PGeneric s a, HasDatatypeInfo (a s), All2 PShow (PCode s a)) =>
  SOP (Term s) (PCode s a) ->
  NonEmpty (Term s PString)
gpshow' (SOP x) =
  let cName = constructorNames !! hindex x
   in pconstant @PString (T.pack cName) :| showSum x
  where
    constructorNames :: [ConstructorName] =
      hcollapse $ hmap (K . constructorName) $ constructorInfo $ datatypeInfo (Proxy @(a s))
    showSum :: NS (NP (Term s)) (PCode s a) -> [Term s PString]
    showSum =
      hcollapse . hcmap (Proxy @(All PShow)) showProd
    showProd :: All PShow xs => NP (Term s) xs -> K [Term s PString] xs
    showProd =
      K . hcollapse . hcmap (Proxy @PShow) showTerm
    showTerm :: forall b. PShow b => Term s b -> K (Term s PString) b
    showTerm =
      K . pshow' True

-- | Group parameters list, preparing for final PShow output
productGroup :: (Monoid a, IsString a) => Bool -> a -> NonEmpty a -> a
productGroup wrap sep = \case
  x :| [] -> x
  xs ->
    let xs' = sconcat $ NE.intersperse sep xs
     in if wrap then fromString "(" <> xs' <> fromString ")" else xs'
