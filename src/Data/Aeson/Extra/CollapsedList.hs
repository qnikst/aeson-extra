{-# LANGUAGE CPP                #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFoldable     #-}
{-# LANGUAGE DeriveFunctor      #-}
{-# LANGUAGE DeriveTraversable  #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Aeson.Extra.CollapsedList
-- Copyright   :  (C) 2015-2016 Oleg Grenrus
-- License     :  BSD3
-- Maintainer  :  Oleg Grenrus <oleg.grenrus@iki.fi>
--
module Data.Aeson.Extra.CollapsedList (
    CollapsedList(..),
    getCollapsedList,
    parseCollapsedList,
    )where

import Prelude        ()
import Prelude.Compat

import Control.Applicative (Alternative(..))
import Data.Aeson.Compat
import Data.Aeson.Types    hiding ((.:?))
import Data.Text           (Text)

#if __GLASGOW_HASKELL__ >= 708
import Data.Typeable       (Typeable)
#endif

import qualified Data.Foldable        as Foldable
import qualified Data.HashMap.Strict  as H

#if MIN_VERSION_aeson(0,10,0)
import qualified Data.Text as T
#endif

-- | Collapsed list, singleton is represented as the value itself in JSON encoding.
--
-- > λ > decode "null" :: Maybe (CollapsedList [Int] Int)
-- > Just (CollapsedList [])
-- > λ > decode "42" :: Maybe (CollapsedList [Int] Int)
-- > Just (CollapsedList [42])
-- > λ > decode "[1, 2, 3]" :: Maybe (CollapsedList [Int] Int)
-- > Just (CollapsedList [1,2,3])
--
-- > λ > encode (CollapsedList ([] :: [Int]))
-- > "null"
-- > λ > encode (CollapsedList ([42] :: [Int]))
-- > "42"
-- > λ > encode (CollapsedList ([1, 2, 3] :: [Int]))
-- > "[1,2,3]"
--
-- Documentation rely on @f@ 'Alternative' instance behaving like lists'.
newtype CollapsedList f a = CollapsedList (f a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable
#if __GLASGOW_HASKELL__ >= 708
           , Typeable
#endif
           )

getCollapsedList :: CollapsedList f a -> f a
getCollapsedList (CollapsedList l) = l

instance (FromJSON a, FromJSON (f a), Alternative f) => FromJSON (CollapsedList f a) where
  parseJSON Null         = pure (CollapsedList Control.Applicative.empty)
  parseJSON v@(Array _)  = CollapsedList <$> parseJSON v
  parseJSON v            = CollapsedList . pure <$> parseJSON v

instance (ToJSON a, ToJSON (f a), Foldable f) => ToJSON (CollapsedList f a) where
#if MIN_VERSION_aeson (0,10,0)
  toEncoding (CollapsedList l) =
    case Foldable.toList l of
      []   -> toEncoding Null
      [x]  -> toEncoding x
      _    -> toEncoding l
#endif
  toJSON (CollapsedList l) =
    case Foldable.toList l of
      []   -> toJSON Null
      [x]  -> toJSON x
      _    -> toJSON l

-- | Parses possibly collapsed array value from the object's field.
--
-- > λ > newtype V = V [Int] deriving (Show)
-- > λ > instance FromJSON V where parseJSON = withObject "V" $ \obj -> V <$> parseCollapsedList obj "value"
-- > λ > decode "{}" :: Maybe V
-- > Just (V [])
-- > λ > decode "{\"value\": null}" :: Maybe V
-- > Just (V [])
-- > λ > decode "{\"value\": 42}" :: Maybe V
-- > Just (V [42])
-- > λ > decode "{\"value\": [1, 2, 3, 4]}" :: Maybe V
-- > Just (V [1,2,3,4])
parseCollapsedList :: (FromJSON a, FromJSON (f a), Alternative f) => Object -> Text -> Parser (f a)
parseCollapsedList obj key =
  case H.lookup key obj of
    Nothing   -> pure Control.Applicative.empty
#if MIN_VERSION_aeson(0,10,0)
    Just v    -> modifyFailure addKeyName $ (getCollapsedList <$> parseJSON v) -- <?> Key key
  where
    addKeyName = (mappend ("failed to parse field " `mappend` T.unpack key `mappend`": "))
#else
    Just v    -> getCollapsedList <$> parseJSON v
#endif
