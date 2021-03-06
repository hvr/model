
[![Build Status](https://travis-ci.org/tittoassini/model.svg?branch=master)](https://travis-ci.org/tittoassini/model)

With `model` you can easily derive models of Haskell data types.

Let's see some code.

We need a couple of GHC extensions:

```haskell
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
```

Import the library:

```haskell
import Data.Model
```

To derive a model of a data type we need to make it an instance of the `Generic` and `Model` classes.

For data types without parameters, we can do it directly in the `deriving` clause of the definition:

```haskell
data Direction = North | South | Center | East | West deriving (Show,Generic,Model)
```

For data types with parameters we currently need a separate instance declaration for `Model`:

```haskell
data Couple a b = Couple a b deriving (Show,Generic)
```

```haskell
instance (Model a,Model b) => Model (Couple a b)
```

Instances for a few common types (Bool,Maybe,Either..) are already predefined.

We use `typeModel` to get the model for the given type plus its full environment, that's to say the models of all the data types referred to, directly or indirectly by the data type.

We pass the type using a Proxy.

```haskell
typeModel (Proxy:: Proxy (Couple Direction Bool))
TypeModel {typeName = TypeApp (TypeApp (TypeCon (QualName {pkgName = "main", mdlName = "Main", locName = "Couple"})) (TypeCon (QualName {pkgName = "main", mdlName = "Main", locName = "Direction"}))) (TypeCon (QualName {pkgName = "ghc-prim", mdlName = "GHC.Types", locName = "Bool"})), typeEnv = fromList [(QualName {pkgName = "ghc-prim", mdlName = "GHC.Types", locName = "Bool"},ADT {declName = "Bool", declNumParameters = 0, declCons = Just (ConTree (Con {constrName = "False", constrFields = Left []}) (Con {constrName = "True", constrFields = Left []}))}),(QualName {pkgName = "main", mdlName = "Main", locName = "Couple"},ADT {declName = "Couple", declNumParameters = 2, declCons = Just (Con {constrName = "Couple", constrFields = Left [TypeCon (TypVar 0),TypeCon (TypVar 1)]})}),(QualName {pkgName = "main", mdlName = "Main", locName = "Direction"},ADT {declName = "Direction", declNumParameters = 0, declCons = Just (ConTree (ConTree (Con {constrName = "North", constrFields = Left []}) (Con {constrName = "South", constrFields = Left []})) (ConTree (Con {constrName = "Center", constrFields = Left []}) (ConTree (Con {constrName = "East", constrFields = Left []}) (Con {constrName = "West", constrFields = Left []}))))})]}
```

That's a lot of information, let's show it in a prettier and more compact way:

```haskell
pPrint $ typeModel (Proxy:: Proxy (Couple Direction Bool))
Type:
main.Main.Couple main.Main.Direction
                 ghc-prim.GHC.Types.Bool -> Couple Direction Bool
Environment:
ghc-prim.GHC.Types.Bool ->  Bool ≡   False
                                   | True
main.Main.Couple ->  Couple a b ≡ Couple a b
main.Main.Direction ->  Direction ≡   North
                                    | South
                                    | Center
                                    | East
                                    | West
```

Data types with symbolic names are also supported:

```haskell
instance (Model a) => Model [a]
```

```haskell
pPrint $ typeModel (Proxy:: Proxy [Bool])
Type:
ghc-prim.GHC.Types.[] ghc-prim.GHC.Types.Bool -> [] Bool
Environment:
ghc-prim.GHC.Types.Bool ->  Bool ≡   False
                                   | True
ghc-prim.GHC.Types.[] ->  [] a ≡   []
                                 | : a (ghc-prim.GHC.Types.[] a)
```

### Installation

Get the latest stable version from [hackage](https://hackage.haskell.org/package/model).

<!--
It is not yet on [hackage](https://hackage.haskell.org/) but you can use it in your [stack](https://docs.haskellstack.org/en/stable/README/) projects by adding in the `stack.yaml` file, under the `packages` section:

````
- location:
   git: https://github.com/tittoassini/model
   commit: b05a56a993213271e3b13d28a5e8bb90c9d8576f
  extra-dep: true
````
-->

### Compatibility

Tested with [ghc](https://www.haskell.org/ghc/) 7.10.3 and 8.0.2.

### Known Bugs and Infelicities

* No support for variables of higher kind.

  For example, we cannot define a `Model` instance for `Higher`:

  `data Higher f a = Higher (f a) deriving Generic`

  as `f` has kind `*->*`:

* Parametric data types cannot derive `Model` in the `deriving` clause and need to define an instance separately

  For example:

  `data Couple a b = Couple a b Bool deriving (Generic,Model)`

  won't work, we need a separate instance:

  `instance (Model a,Model b) => Model (Couple a b)`

* Works incorrectly with data types with more than 9 type variables.
