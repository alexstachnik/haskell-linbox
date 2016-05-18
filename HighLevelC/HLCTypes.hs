{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FunctionalDependencies #-}

module HighLevelC.HLCTypes where

import Language.C.Pretty(Pretty,pretty)
import Text.PrettyPrint.HughesPJ

import Data.List
import Data.Typeable

import qualified Data.Map as M
import qualified Data.Set as S

import Util.Names
import IntermediateLang.ILTypes

data Argument = Argument {argumentName :: HLCSymbol,
                          argumentType :: ILType}
              deriving (Eq,Ord,Show)

data Variable = Variable {variableName :: HLCSymbol,
                          variableType :: ILType,
                          variableArrLen :: Maybe HLCExpr}
              deriving (Eq,Ord,Show)

data StructField = StructField {fieldName :: SafeName,
                                fieldType :: ILType,
                                fieldArrLen :: Maybe Integer}
                   deriving (Eq,Ord,Show)

newtype TypedStructField a = TypedStructField {fromTypedStructField :: StructField}

newtype FuncBaseName = FuncBaseName {fromFuncBaseName :: String}
                     deriving (Eq,Ord,Show)

newtype StructBaseName = StructBaseName {fromStructBaseName :: String}
                       deriving (Eq,Ord,Show)

data FunctionInst = FunctionInst FuncBaseName [ILType]
                  deriving (Eq,Ord,Show)

newtype FuncInstances = FuncInstances {fromFuncInstances :: M.Map FunctionInst HLCSymbol}
                  deriving (Eq,Ord,Show)

newtype StructInstances = StructInstances {fromStructInstances :: S.Set StructDef}
                        deriving (Show,Eq,Ord)

newtype TW a = TW {fromTW :: ILType}

class (Typeable a) => HLCTypeable a where
  hlcType :: TW a
  structDef :: Maybe (TypedStructDef a)
  hlcType = TW $ BaseType NotConst
    (ILStructRef $ getILType (Proxy :: Proxy a))

getObjType :: forall a. (HLCTypeable a) => a -> ILType
getObjType _ = fromTW (hlcType :: TW a)
  
newtype TypedVar a = TypedVar {fromTypedVar :: HLCSymbol} deriving (Eq,Ord,Show)

instance (HLCTypeable a) => HLCTypeable (TypedExpr a) where
  hlcType = TW $ fromTW (hlcType :: TW a)
  structDef = (structDef :: Maybe (TypedStructDef a)) >>=
    (return . TypedStructDef . fromTypedStructDef)

data FunctionProto = FunctionProto ILType HLCSymbol [Argument]
                      deriving (Show,Eq,Ord)

data StructProto = StructProto ILTypeName
                 deriving (Show,Eq,Ord)

data StructDef = StructDef ILTypeName [StructField]
               deriving (Eq,Ord,Show)

newtype TypedStructDef a = TypedStructDef {fromTypedStructDef :: StructDef}

data FunctionDef = FunctionDef {functionRetType :: ILType,
                                functionName :: HLCSymbol,
                                functionArguments :: [Argument],
                                functionLocalVars :: [Variable],
                                functionStmts :: [HLCStatement],
                                functionObjectManagers :: [ObjectManager]}
                 deriving (Show,Eq,Ord)

data HLCStatement = HLCBlock [Variable] [ObjectManager] [HLCStatement]
                  | HLCExpStmt HLCExpr
                  | HLCAssignment UntypedLHS HLCExpr
                  | HLCLabel HLCStatement
                  deriving (Eq,Ord,Show)

data UntypedLHS = LHSVar HLCSymbol
                | LHSDeref UntypedLHS
                | LHSDerefPlusOffset UntypedLHS Integer
                | LHSElement UntypedLHS SafeName
                deriving (Eq,Ord,Show)

data HLCExpr = ExpVar HLCSymbol
             | FunctionCall HLCExpr [HLCExpr]
             | LitExpr HLCLit
             | AccessPart HLCExpr SafeName
             | SizeOf ILType
             | ExprBinOp HLCBinOp HLCExpr HLCExpr
             | HLCCast ILType HLCExpr
             | Void
             deriving (Eq,Ord,Show)

data HLCBinOp = HLCPlus
              | HLCMinus
              | HLCTimes
              | HLCDivide
              | HLCRem
              | HLCLAnd
              | HLCLOr
              | HLCBitAnd
              | HLCBitOr
              | HLCBitXor
              deriving (Eq,Ord,Show)

data HLCLit = CharLit Char
            | IntLit Integer
            | DoubleLit Double
            | StrLit String
            deriving (Eq,Ord,Show)

varRef :: TypedVar a -> TypedExpr a
varRef = TypedExpr . ExpVar . fromTypedVar

newtype HLCPointer a = HLCPointer a

deriving instance (Show a) => Show (HLCPointer a)
deriving instance (Eq a) => Eq (HLCPointer a)
deriving instance (Ord a) => Ord (HLCPointer a)

instance (HLCTypeable a) => HLCTypeable (HLCPointer a) where
  hlcType = TW $ PtrType NotConst $ fromTW (hlcType :: TW a)
  structDef = Nothing

data TypedLHS a where
  TypedLHSVar :: TypedVar a -> TypedLHS a
  TypedLHSDeref :: TypedLHS (HLCPointer a) -> TypedLHS a
  TypedLHSDerefPlusOffset :: TypedLHS (HLCPointer a) -> Integer -> TypedLHS a
  TypedLHSElement :: (Typeable fieldName,
                      Struct structType fieldName fieldType) =>
                     TypedLHS structType -> Proxy fieldName -> TypedLHS fieldType

data ObjectManager = ObjectManager {constructor :: [HLCStatement],
                                    destructor :: [HLCStatement]}
                   deriving (Show,Eq,Ord)

class (Typeable name) => HLCFunction name ty | name -> ty where
  call :: Proxy name -> ty

--data Foo
--instance Function Foo (Int -> Int -> String) where
--  call _ n m = show (n+m)


--call2 name a1 a2 = (call name) a1 a2

newtype TypedExpr a = TypedExpr {fromTypedExpr :: HLCExpr}

class (Typeable fieldName) =>
      Struct structType fieldName fieldType | structType fieldName -> fieldType

data VarArg = forall a . ConsArg (TypedExpr a) VarArg
            | NilArg

varArgToList :: VarArg -> [HLCExpr]
varArgToList NilArg = []
varArgToList (ConsArg typedExpr rest) =
  fromTypedExpr typedExpr :
  varArgToList rest

getILType :: forall a. (Typeable a) => Proxy a -> ILTypeName
getILType _ =
  ILTypeName $ fromSafeName $ makeSafeName $ show $
  typeRep (Proxy :: Proxy a)

getFieldName :: forall a. (Typeable a) => Proxy a -> SafeName
getFieldName _ = makeSafeName $ show $ typeRep (Proxy :: Proxy a)

emptyFuncInstances :: FuncInstances
emptyFuncInstances = FuncInstances M.empty

emptyStructInstances :: StructInstances
emptyStructInstances = StructInstances S.empty

makeFuncBaseName :: String -> FuncBaseName
makeFuncBaseName = FuncBaseName . fromSafeName . makeSafeName

makeStructBaseName :: String -> StructBaseName
makeStructBaseName = StructBaseName . fromSafeName . makeSafeName

deriveFuncName :: FuncBaseName -> [ILType] -> SafeName
deriveFuncName (FuncBaseName baseName) args =
  joinSafeNames
  (SafeName baseName :
   map (makeSafeName . trim . show . pretty . writeDecl "") args)

deriveStructName :: StructBaseName -> [ILType] -> ILTypeName
deriveStructName (StructBaseName baseName) args =
  ILTypeName $ fromSafeName $ joinSafeNames
  (SafeName baseName:
   map (makeSafeName . trim . show . pretty . writeDecl "") args)
