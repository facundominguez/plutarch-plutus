{-# OPTIONS_GHC -Wno-orphans #-}

module Plutarch.Rational (
  PRational,
  preduce,
  pnumerator,
  pdenominator,
  pfromInteger,
) where

import Plutarch.Prelude

import Data.Ratio (denominator, numerator)
import Plutarch (PlutusType (..))
import Plutarch.Bool (PEq (..), POrd (..), pif)
import Plutarch.Integer (PInteger, PIntegral (pdiv, pmod))

data PRational s = PRational (Term s PInteger) (Term s PInteger)

instance PlutusType PRational where
  type PInner PRational c = (PInteger :--> PInteger :--> c) :--> c
  pcon' (PRational x y) = plam $ \f -> f # x # y
  pmatch' p f = p #$ plam $ \x y -> f (PRational x y)

instance PEq PRational where
  l' #== r' =
    phoistAcyclic
      ( plam $ \l r ->
          pmatch l $ \(PRational ln ld) ->
            pmatch r $ \(PRational rn rd) ->
              rd * ln #== rn * ld
      )
      # l'
      # r'

instance POrd PRational where
  l' #<= r' =
    phoistAcyclic
      ( plam $ \l r ->
          pmatch l $ \(PRational ln ld) ->
            pmatch r $ \(PRational rn rd) ->
              rd * ln #<= rn * ld
      )
      # l'
      # r'

  l' #< r' =
    phoistAcyclic
      ( plam $ \l r ->
          pmatch l $ \(PRational ln ld) ->
            pmatch r $ \(PRational rn rd) ->
              rd * ln #< rn * ld
      )
      # l'
      # r'

instance Num (Term s PRational) where
  x' + y' =
    phoistAcyclic
      ( plam $ \x y ->
          preduce #$ pmatch x $
            \(PRational xn xd) ->
              pmatch y $ \(PRational yn yd) ->
                pcon $ PRational (xn * yd + yn * xd) (xd * yd)
      )
      # x'
      # y'

  x' - y' =
    phoistAcyclic
      ( plam $ \x y ->
          preduce
            #$ pmatch x
            $ \(PRational xn xd) ->
              pmatch y $ \(PRational yn yd) ->
                pcon $ PRational (xn * yd - yn * xd) (xd * yd)
      )
      # x'
      # y'

  x' * y' =
    phoistAcyclic
      ( plam $ \x y ->
          preduce
            #$ pmatch x
            $ \(PRational xn xd) ->
              pmatch y $ \(PRational yn yd) ->
                pcon $ PRational (xn * yn) (xd * yd)
      )
      # x'
      # y'

  negate x' =
    phoistAcyclic
      ( plam $ \x ->
          pmatch x $ \(PRational xn xd) ->
            pcon $ PRational (negate xn) xd
      )
      # x'

  abs x' =
    phoistAcyclic
      ( plam $ \x ->
          pmatch x $ \(PRational xn xd) ->
            pcon $ PRational (abs xn) (abs xd)
      )
      # x'

  signum x'' =
    phoistAcyclic
      ( plam $ \x' -> plet x' $ \x ->
          pif
            (x #== 0)
            0
            $ pif
              (x #< 0)
              (-1)
              1
      )
      # x''

  fromInteger n = pcon $ PRational (fromInteger n) 1

instance Fractional (Term s PRational) where
  recip x' =
    phoistAcyclic
      ( plam $ \x ->
          pmatch x $ \(PRational xn xd) ->
            pcon (PRational xd xn)
      )
      # x'

  x' / y' =
    phoistAcyclic
      ( plam $ \x y ->
          preduce
            #$ pmatch x
            $ \(PRational xn xd) ->
              pmatch y $ \(PRational yn yd) ->
                pcon (PRational (xn * yd) (xd * yn))
      )
      # x'
      # y'

  fromRational r =
    pcon $ PRational (fromInteger $ numerator r) (fromInteger $ denominator r)

preduce :: Term s (PRational :--> PRational)
preduce = phoistAcyclic $
  plam $ \x ->
    pmatch x $ \(PRational xn xd) ->
      plet (pgcd # xn # xd) $ \r ->
        plet (signum xd) $ \s ->
          pcon $ PRational (s * pdiv # xn # r) (s * pdiv # xd # r)

pgcd :: Term s (PInteger :--> PInteger :--> PInteger)
pgcd = phoistAcyclic $
  plam $ \x' y' ->
    plet (abs x') $ \x ->
      plet (abs y') $ \y ->
        plet (pmax # x # y) $ \a ->
          plet (pmin # x # y) $ \b ->
            pgcd' # a # b

-- assumes inputs are non negative and a >= b
pgcd' :: Term s (PInteger :--> PInteger :--> PInteger)
pgcd' = phoistAcyclic $ pfix #$ plam $ f
  where
    f self a b =
      pif
        (b #== 0)
        a
        $ self # b #$ pmod # a # b

pmin :: POrd a => Term s (a :--> a :--> a)
pmin = phoistAcyclic $ plam $ \a b -> pif (a #<= b) a b

pmax :: POrd a => Term s (a :--> a :--> a)
pmax = phoistAcyclic $ plam $ \a b -> pif (a #<= b) b a

pnumerator :: Term s (PRational :--> PInteger)
pnumerator = phoistAcyclic $ plam $ \x -> pmatch x $ \(PRational n _) -> n

pdenominator :: Term s (PRational :--> PInteger)
pdenominator = phoistAcyclic $ plam $ \x -> pmatch x $ \(PRational _ d) -> d

pfromInteger :: Term s (PInteger :--> PRational)
pfromInteger = phoistAcyclic $ plam $ \n -> pcon $ PRational n 1
