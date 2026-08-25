//

//  SupabaseService.swift

//  Ponder

//

import Foundation

import Supabase

import Auth

final class SupabaseService {

    static let shared = SupabaseService()

    static let projectURL = URL(string: "https://hybjzmgkzdkpjpaudzdv.supabase.co")!
    static let publishableKey = "sb_publishable_prJwbQ2CinxukH0hMcEDgw_9-3ViFrg"

    let client: SupabaseClient

    private init() {

        client = SupabaseClient(

            supabaseURL: Self.projectURL,

            supabaseKey: Self.publishableKey,

            options: SupabaseClientOptions(

                auth: SupabaseClientOptions.AuthOptions(

                    autoRefreshToken: true,

                    emitLocalSessionAsInitialSession: true

                )

            )

        )

    }

}
