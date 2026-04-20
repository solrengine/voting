import { application } from "./application"

// Shared controllers from @solrengine/wallet-utils
import { WalletController, SendTransactionController } from "@solrengine/wallet-utils/controllers"
application.register("wallet", WalletController)
application.register("send-transaction", SendTransactionController)

// UI controllers from @solrengine/ui
import { registerControllers } from "@solrengine/ui"
registerControllers(application)

// Voting dApp: per-candidate vote action
import VotingController from "./voting_controller"
application.register("voting", VotingController)
