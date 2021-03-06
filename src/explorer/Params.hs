-- | Getter params from Args

module Params
       ( gtSscParams
       , getLoggingParams
       , getNodeParams
       , getBaseParams
       , getKademliaParams
       , getPeersFromArgs
       ) where

import           Universum

import           System.Wlog           (LoggerName, WithLogger)

import qualified Data.ByteString.Char8 as BS8 (unpack)
import qualified Data.Set              as S (fromList)
import qualified Network.Transport.TCP as TCP (TCPAddr (..), TCPAddrInfo (..))
import qualified Pos.CLI               as CLI
import           Pos.Constants         (isDevelopment)
import           Pos.Core.Types        (Timestamp (..))
import           Pos.Crypto            (VssKeyPair)
import           Pos.DHT.Real          (KademliaParams (..))
import           Pos.Genesis           (devAddrDistr, devStakesDistr,
                                        genesisProdAddrDistribution,
                                        genesisProdBootStakeholders, genesisUtxo)
import           Pos.Launcher          (BaseParams (..), LoggingParams (..),
                                        NetworkParams (..), NodeParams (..))
import           Pos.Security.Params   (SecurityParams (..))
import           Pos.Ssc.GodTossing    (GtParams (..))
import           Pos.Update.Params     (UpdateParams (..))
import           Pos.Util.TimeWarp     (NetworkAddress, addressToNodeId, readAddrFile)
import           Pos.Util.UserSecret   (peekUserSecret)


import           ExplorerOptions       (Args (..))
import           Secrets               (updateUserSecretVSS, userSecretWithGenesisKey)

gtSscParams :: Args -> VssKeyPair -> GtParams
gtSscParams Args {..} vssSK =
    GtParams
    { gtpSscEnabled = True
    , gtpVssKeyPair = vssSK
    }

getBaseParams :: LoggerName -> Args -> BaseParams
getBaseParams loggingTag args@Args {..} =
    BaseParams { bpLoggingParams = getLoggingParams loggingTag args }

getLoggingParams :: LoggerName -> Args -> LoggingParams
getLoggingParams tag Args{..} =
    LoggingParams
    { lpHandlerPrefix = CLI.logPrefix commonArgs
    , lpConfigPath    = CLI.logConfig commonArgs
    , lpRunnerTag = tag
    }

getPeersFromArgs :: Args -> IO [NetworkAddress]
getPeersFromArgs Args {..} = do
    filePeers <- maybe (pure []) readAddrFile dhtPeersFile
    pure $ dhtPeersList ++ filePeers

-- | Load up the KademliaParams. It's in IO because we may have to read a
--   file to find some peers.
getKademliaParams :: Args -> IO KademliaParams
getKademliaParams args@Args{..} = do
    allPeers <- getPeersFromArgs args
    pure $ KademliaParams
                 { kpNetworkAddress  = dhtNetworkAddress
                 , kpPeers           = allPeers
                 , kpKey             = dhtKey
                 , kpExplicitInitial = dhtExplicitInitial
                 , kpDump            = kademliaDumpPath
                 , kpExternalAddress = externalAddress
                 }
getNetworkParams :: Args -> IO NetworkParams
getNetworkParams args
    | staticPeers args = do
        allPeers <- S.fromList . map addressToNodeId <$> getPeersFromArgs args
        return
            NetworkParams
            {npDiscovery = Left allPeers, npTcpAddr = TCP.Unaddressable}
    | otherwise = do
        let (bindHost, bindPort) = bindAddress args
        let (externalHost, externalPort) = externalAddress args
        let tcpAddr =
                TCP.Addressable $
                TCP.TCPAddrInfo
                    (BS8.unpack bindHost)
                    (show $ bindPort)
                    (const (BS8.unpack externalHost, show $ externalPort))
        kademliaParams <- getKademliaParams args
        return
            NetworkParams
            {npDiscovery = Right kademliaParams, npTcpAddr = tcpAddr}

getNodeParams
    :: (MonadIO m, MonadFail m, MonadThrow m, WithLogger m)
    => Args -> Timestamp -> m NodeParams
getNodeParams args@Args {..} systemStart = do
    (primarySK, userSecret) <-
        userSecretWithGenesisKey args =<<
        updateUserSecretVSS args =<<
        peekUserSecret keyfilePath
    let devStakeDistr =
            devStakesDistr
                (CLI.flatDistr commonArgs)
                (CLI.bitcoinDistr commonArgs)
                (CLI.richPoorDistr commonArgs)
                (CLI.expDistr commonArgs)
    npNetwork <- liftIO $ getNetworkParams args
    return NodeParams
        { npDbPathM = dbPath
        , npRebuildDb = rebuildDB
        , npSecretKey = primarySK
        , npUserSecret = userSecret
        , npSystemStart = systemStart
        , npBaseParams = getBaseParams "node" args
        , npCustomUtxo =
            if isDevelopment
            then genesisUtxo Nothing (devAddrDistr devStakeDistr)
            else genesisUtxo (Just genesisProdBootStakeholders)
                                genesisProdAddrDistribution
        , npJLFile = jlPath
        , npPropagation = not (CLI.disablePropagation commonArgs)
        , npUpdateParams = UpdateParams
            { upUpdatePath = "explorer-update"
            , upUpdateWithPkg = True
            , upUpdateServers = CLI.updateServers commonArgs
            }
        , npReportServers = CLI.reportServers commonArgs
        , npSecurityParams = SecurityParams
            { spAttackTypes   = []
            , spAttackTargets = []
            }
          , npUseNTP = not noNTP
          , npEnableMetrics = enableMetrics
          , npEkgParams = ekgParams
          , npStatsdParams = statsdParams
          , ..
        }
