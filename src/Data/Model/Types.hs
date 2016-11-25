{- |A model for simple algebraic data types.
-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveFoldable    #-}
{-# LANGUAGE DeriveFunctor     #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DeriveTraversable ,FlexibleInstances #-}
module Data.Model.Types(
  -- *Model
  TypeModel(..),TypeEnv
  ,ADT(..)
  ,ConTree(..)
  ,Type(..),TypeN(..),TypeRef(..)

  -- *Names
  ,Name(..),QualName(..),qualName

  -- *Model Utilities
  ,adtNamesMap
  --,typeADTs
  ,typeN,typeA
  ,constructors,conTreeNameMap,conTreeTypeMap,conTreeTypeList,conTreeTypeFoldMap,fieldsTypes,fieldsNames

  -- *Handy aliases
  ,HTypeEnv,HTypeModel,HADT,HType,HTypeRef
  -- ,HEnv

  -- *Utilities
  ,solve,solveAll,unVar

  -- *Re-exports
  ,module GHC.Generics,Proxy(..)
  -- ,S.StringLike(),S.toString,S.fromString
  ) where

import           Control.DeepSeq
import           Data.Bifunctor  (first,second)
import           Data.Proxy
import           Data.Word       (Word8)
import           GHC.Generics
import qualified Data.Map as M
import qualified Data.ListLike.String           as S
import Data.List

-- |Haskell Environment
type HTypeEnv = TypeEnv String String (TypeRef QualName) QualName

-- |Haskell TypeModel
type HTypeModel = TypeModel String String (TypeRef QualName) QualName

-- |Haskell ADT
type HADT = ADT String String HTypeRef

-- |Haskell Type
type HType = Type HTypeRef

-- |Reference to an Haskell Type
type HTypeRef = TypeRef QualName

{- |
The complete model of a type, a reference to the type plus its environment:

* adtName:  type used to represent the name of a data type
* consName: type used to represent the name of a constructor
* inRef:    type used to represent a reference to a type or a type variable inside the data type definition (for example `HTypeRef`)
* exRef:    type used to represent a reference to a type in the type name (for example `QualName`)
-}
data TypeModel adtName consName inRef exRef = TypeModel {
  -- |The type application corresponding to the type
  typeName::Type exRef

  -- |The environment in which the type is defined
  ,typeEnv::TypeEnv adtName consName inRef exRef
  }
  deriving (Eq, Ord, Show, NFData, Generic)

--typeADTs = M.elems . typeEnv

-- |A map of all the ADTs that are directly or indirectly referred by a type, indexed by a type reference
type TypeEnv adtName consName inRef exRef = M.Map exRef (ADT adtName consName inRef)

{- |
Simple algebraic data type (not a GADT):

* declName: type used to represent the name of the data type
* consName: type used to represent the name of a constructor
* ref:      type used to represent a reference to a type or a type variable inside the data type definition (for example `HTypeRef`)
-}
data ADT name consName ref =
       ADT
         { declName          :: name   -- ^The name of the data type (for example @Bool@ for @data Bool@)
         , declNumParameters :: Word8  -- ^The number of type parameters/variable (up to a maximum of 255)
         , declCons          :: Maybe (ConTree consName ref) -- ^The constructors, if present
         }
       deriving (Eq, Ord, Show, NFData, Generic, Functor, Foldable, Traversable)

-- |Constructors are assembled in a binary tree
data ConTree name ref =
  Con {
  -- | The constructor name, unique in the data type
  constrName    :: name

  -- | Constructor fields, they can be either unnamed (Left case) or named (Right case)
  -- If they are named, they must all be named
  ,constrFields :: Either
                   [Type ref]
                   [(name,Type ref)]
  }

  {- |
  Constructor tree.

  Constructors are disposed in an optimally balanced, right heavier tree:

  For example, the data type:

  @data N = One | Two | Three | Four | Five@

  Would have its contructors ordered in the following tree:

>          |
>     |            |
>  One Two   Three   |
>                Four Five

  To get a list of constructor in declaration order, use `constructors`
  -}
  | ConTree (ConTree name ref) (ConTree name ref)

  deriving (Eq, Ord, Show, NFData, Generic)

-- |Return the list of constructors in definition order
constructors c@(Con _ _) = [c]
constructors (ConTree l r) = constructors l ++ constructors r

-- |Return just the field types
fieldsTypes :: Either [b] [(a, b)] -> [b]
fieldsTypes (Left ts)   = ts
fieldsTypes (Right nts) = map snd nts

-- |Return just the field names (or an empty list if unspecified)
fieldsNames (Left _)   = []
fieldsNames (Right nts) = map snd nts

-- GHC won't derive these instances automatically
instance Functor (ConTree name) where
  fmap f (ConTree l r) = ConTree (fmap f l) (fmap f r)
  fmap f (Con n (Left ts)) = Con n (Left $ (fmap . fmap) f ts)
  fmap f (Con n (Right ts)) = Con n (Right $ (fmap . fmap . fmap) f ts)

instance Foldable (ConTree name) where
   foldMap f (ConTree l r) = foldMap f l `mappend` foldMap f r
   foldMap f (Con _ (Left ts)) = mconcat . map (foldMap f) $ ts
   foldMap f (Con _ (Right nts)) = mconcat . map (foldMap f . snd) $ nts

instance Traversable (ConTree name) where
  traverse f (ConTree l r) = ConTree <$> traverse f l <*> traverse f r
  traverse f (Con n (Left ts)) = Con n . Left <$> sequenceA (map (traverse f) ts)
  -- TODO: simplify this
  traverse f (Con n (Right nts)) = Con n . Right . zip (map fst nts) <$> sequenceA (map (traverse f . snd) nts)

-- CHECK: easier to use lens?
-- |Map on the constructor types (used for example when eliminating variables)
conTreeTypeMap :: (Type t -> Type ref) -> ConTree name t -> ConTree name ref
conTreeTypeMap f (ConTree l r) = ConTree (conTreeTypeMap f l) (conTreeTypeMap f r)
conTreeTypeMap f (Con n (Left ts)) = Con n (Left $ map f ts)
conTreeTypeMap f (Con n (Right nts)) = Con n (Right $ map (second f) nts)

-- |Map over a constructor tree names
conTreeNameMap :: (name -> name2) -> ConTree name t -> ConTree name2 t
conTreeNameMap f (ConTree l r) = ConTree (conTreeNameMap f l) (conTreeNameMap f r)
conTreeNameMap f (Con n (Left ts)) = Con (f n) (Left ts)
conTreeNameMap f (Con n (Right nts)) = Con (f n) (Right $ map (first f) nts)

-- |Extract list of types in a constructor tree
conTreeTypeList :: ConTree name t -> [Type t]
conTreeTypeList = conTreeTypeFoldMap (:[])

-- |Fold over the types in a constructor tree
conTreeTypeFoldMap :: Monoid a => (Type t -> a) -> ConTree name t -> a
conTreeTypeFoldMap f (ConTree l r) = conTreeTypeFoldMap f l `mappend` conTreeTypeFoldMap f r
conTreeTypeFoldMap f (Con _ (Left ts)) = mconcat . map f $ ts
conTreeTypeFoldMap f (Con _ (Right nts)) = mconcat . map (f . snd) $ nts

-- |Map over the names of an ADT and of its constructors
adtNamesMap
  :: (adtName1 -> adtName2)
     -> (consName1 -> consName2)
     -> ADT adtName1 consName1 ref
     -> ADT adtName2 consName2 ref
adtNamesMap f g adt = adt {declName = f (declName adt),declCons = conTreeNameMap g <$> declCons adt}

-- |A type
data Type ref = TypeCon ref                    -- ^Type constructor ("Bool","Maybe",..)
              | TypeApp (Type ref) (Type ref)  -- ^Type application
  deriving (Eq, Ord, Show, NFData, Generic, Functor, Foldable, Traversable)

-- |Another representation of a type, sometime easier to work with
data TypeN r = TypeN r [TypeN r]
             deriving (Eq,Ord,Read,Show,NFData ,Generic,Functor,Foldable,Traversable)

-- |Convert from Type to TypeN
typeN :: Type r -> TypeN r
typeN (TypeApp f a) = let TypeN h ts = typeN f
                       in TypeN h (ts ++ [typeN a])
typeN (TypeCon r) = TypeN r []

-- |Convert from TypeN to Type
typeA :: TypeN ref -> Type ref
typeA (TypeN t ts) = app (TypeCon t) (map typeA ts)
  where app t [] = t
        app t (x:xs) = app (TypeApp t x) xs

-- |A reference to a type
data TypeRef name = TypVar Word8  -- ^Type variable
                  | TypRef name   -- ^Type reference
  deriving (Eq, Ord, Show, NFData, Generic, Functor, Foldable, Traversable)

-- |A fully qualified Haskell name
data QualName = QualName {pkgName,mdlName,locName :: String}
              deriving (Eq, Ord, Show, NFData, Generic)

-- |Return the qualified name, minus the package name.
qualName :: QualName -> String
qualName n = concat [mdlName n,".",locName n]

instance S.StringLike QualName where
  toString n = intercalate "." [pkgName n,mdlName n,locName n]
  fromString n = let (p,r) = span (/= '.') n
                     (m,r2) = span (/= '.') $ tail r
                     l = tail r2
                 in QualName p m l

instance S.StringLike String where
  toString = id
  fromString = id

-- |Simple name
data Name = Name String deriving (Eq, Ord, Show, NFData, Generic)

instance S.StringLike Name where
  toString (Name n)= n
  fromString n = Name n

-- Utilities

-- |Remove variable references (for example if we know that a type is fully saturated and cannot contain variables)
unVar (TypVar _) = error "Unexpected variable"
unVar (TypRef n) = n

-- |Solve all references in a data structure, using the given environment
solveAll :: (Functor f, Show k, Ord k) => M.Map k b -> f k -> f b
solveAll env t = (\r -> solve r env) <$> t

-- |Solve a key in an environment, returns an error if the key is missing
solve :: (Ord k, Show k) => k -> M.Map k a -> a
solve k e = case M.lookup k e of
     Nothing -> error $ unwords ["Unknown reference to",show k]
     Just v -> v
