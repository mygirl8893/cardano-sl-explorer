{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeOperators       #-}

module Pos.Explorer.Web.TestServer (runMockServer) where

import           Data.Time                      (defaultTimeLocale,
                                                 parseTimeOrError)
import           Data.Time.Clock.POSIX          (POSIXTime,
                                                 utcTimeToPOSIXSeconds)
import           Network.Wai                    (Application)
import           Network.Wai.Handler.Warp       (run)
import           Pos.Explorer.Aeson.ClientTypes ()
import           Pos.Explorer.Web.Api           (ExplorerApi, explorerApi)
import           Pos.Explorer.Web.ClientTypes   (CAddress (..),
                                                 CAddressSummary (..),
                                                 CBlockEntry (..),
                                                 CBlockSummary (..), CHash (..),
                                                 CTxBrief (..), CTxEntry (..),
                                                 CTxId (..), CTxSummary (..))
import           Pos.Explorer.Web.Error         (ExplorerError (..))
import           Pos.Types                      (EpochIndex, mkCoin)
import           Pos.Web                        ()
import           Servant.API                    ((:<|>) ((:<|>)))
import           Servant.Server                 (Handler, Server, serve)
import           Universum


----------------------------------------------------------------
-- Top level functionality
----------------------------------------------------------------

-- Run the server. Must be on the same port so we don't have to modify anything
runMockServer :: IO ()
runMockServer = run 8100 explorerApp

explorerApp :: Application
explorerApp = serve explorerApi explorerHandlers

----------------------------------------------------------------
-- Handlers
----------------------------------------------------------------

explorerHandlers :: Server ExplorerApi
explorerHandlers =
      apiBlocksLast
    :<|>
      apiBlocksSummary
    :<|>
      apiBlocksTxs
    :<|>
      apiTxsLast
    :<|>
      apiTxsSummary
    :<|>
      apiAddressSummary
    :<|>
      apiEpochSlotSearch
  where
    apiBlocksLast       = testBlocksLast
    apiBlocksSummary    = testBlocksSummary
    apiBlocksTxs        = testBlocksTxs
    apiTxsLast          = testTxsLast
    apiTxsSummary       = testTxsSummary
    apiAddressSummary   = testAddressSummary
    apiEpochSlotSearch  = testEpochSlotSearch

--------------------------------------------------------------------------------
-- sample data --
--------------------------------------------------------------------------------
posixTime :: POSIXTime
posixTime = utcTimeToPOSIXSeconds (parseTimeOrError True defaultTimeLocale "%F" "2017-12-03")

sampleAddressSummary :: CAddressSummary
sampleAddressSummary = CAddressSummary
    { caAddress = CAddress "1fi9sA3pRt8bKVibdun57iyWG9VsWZscgQigSik6RHoF5Mv"
    , caTxNum   = 0
    , caBalance = mkCoin 0
    , caTxList  = []
    }
----------------------------------------------------------------
-- Test handlers
----------------------------------------------------------------

testBlocksLast
    :: Maybe Word
    -> Maybe Word
    -> Handler (Either ExplorerError [CBlockEntry])
testBlocksLast _ _  = pure . pure $ [CBlockEntry
    { cbeEpoch      = 37294
    , cbeSlot       = 10
    , cbeBlkHash    = CHash "75aa93bfa1bf8e6aa913bc5fa64479ab4ffc1373a25c8176b61fa1ab9cbae35d"
    , cbeTimeIssued = Nothing
    , cbeTxNum      = 0
    , cbeTotalSent  = mkCoin 0
    , cbeSize       = 390
    , cbeRelayedBy  = Nothing
    }]

testBlocksSummary
    :: CHash
    -> Handler (Either ExplorerError CBlockSummary)
testBlocksSummary _ = pure . pure $ CBlockSummary
    { cbsEntry      = CBlockEntry
                        { cbeEpoch      = 37294
                        , cbeSlot       = 10
                        , cbeBlkHash    = CHash "75aa93bfa1bf8e6aa913bc5fa64479ab4ffc1373a25c8176b61fa1ab9cbae35d"
                        , cbeTimeIssued = Nothing
                        , cbeTxNum      = 0
                        , cbeTotalSent  = mkCoin 0
                        , cbeSize       = 390
                        , cbeRelayedBy  = Nothing
                        }
    , cbsPrevHash   = CHash "d36710c918da4c4a3e0ff42e1049d81cc7bcbacc789c8583ea1c9afd8da3c24e"
    , cbsNextHash   = Just (CHash "d3bb988e57356b706f7b8f1fe29591ab0d1bdfac4aa08836475783973e4cf7c1")
    , cbsMerkleRoot = CHash "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9"
    }

testBlocksTxs
    :: CHash
    -> Maybe Word
    -> Maybe Word
    -> Handler (Either ExplorerError [CTxBrief])
testBlocksTxs _ _ _ = pure . pure $ [CTxBrief
    { ctbId         = CTxId $ CHash "b29fa17156275a8589857376bfaeeef47f1846f82ea492a808e5c6155b450e02"
    , ctbTimeIssued = posixTime
    , ctbInputs     = [(CAddress "1fi9sA3pRt8bKVibdun57iyWG9VsWZscgQigSik6RHoF5Mv", mkCoin 33333)]
    , ctbOutputs    = [(CAddress "1fSCHaQhy6L7Rfjn9xR2Y5H7ZKkzKLMXKYLyZvwWVffQwkQ", mkCoin 33333)]
    }]

testTxsLast
    :: Maybe Word
    -> Maybe Word
    -> Handler (Either ExplorerError [CTxEntry])
testTxsLast _ _     = pure . pure $ [CTxEntry
    { cteId         = CTxId $ CHash "b29fa17156275a8589857376bfaeeef47f1846f82ea492a808e5c6155b450e02"
    , cteTimeIssued = posixTime
    , cteAmount     = mkCoin 33333
    }]

testTxsSummary
    :: CTxId
    -> Handler (Either ExplorerError CTxSummary)
testTxsSummary _       = pure . pure $ CTxSummary
    { ctsId              = CTxId $ CHash "b29fa17156275a8589857376bfaeeef47f1846f82ea492a808e5c6155b450e02"
    , ctsTxTimeIssued    = posixTime
    , ctsBlockTimeIssued = Nothing
    , ctsBlockHeight     = Just 11
    , ctsRelayedBy       = Nothing
    , ctsTotalInput      = mkCoin 33333
    , ctsTotalOutput     = mkCoin 33333
    , ctsFees            = mkCoin 0
    , ctsInputs          = [(CAddress "1fi9sA3pRt8bKVibdun57iyWG9VsWZscgQigSik6RHoF5Mv", mkCoin 33333)]
    , ctsOutputs         = [(CAddress "1fSCHaQhy6L7Rfjn9xR2Y5H7ZKkzKLMXKYLyZvwWVffQwkQ", mkCoin 33333)]
    }

testAddressSummary
    :: CAddress
    -> Handler (Either ExplorerError CAddressSummary)
testAddressSummary _  = pure . pure $ sampleAddressSummary

testEpochSlotSearch
    :: EpochIndex
    -> Maybe Word16
    -> Handler (Either ExplorerError [CBlockEntry])
testEpochSlotSearch _ _ = pure . pure $ [CBlockEntry
    { cbeEpoch      = 37294
    , cbeSlot       = 10
    , cbeBlkHash    = CHash "75aa93bfa1bf8e6aa913bc5fa64479ab4ffc1373a25c8176b61fa1ab9cbae35d"
    , cbeTimeIssued = Nothing
    , cbeTxNum      = 0
    , cbeTotalSent  = mkCoin 0
    , cbeSize       = 390
    , cbeRelayedBy  = Nothing
    }]