//

//  SupabaseService.swift

//  Ponder

//

import Foundation

import Supabase

import Auth

final class SupabaseService {

    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {

        client = SupabaseClient(

            supabaseURL: URL(string: "https://hybjzmgkzdkpjpaudzdv.supabase.co")!,

            supabaseKey: "sb_publishable_prJwbQ2CinxukH0hMcEDgw_9-3ViFrg",

            options: SupabaseClientOptions(

                auth: SupabaseClientOptions.AuthOptions(

                    autoRefreshToken: true,

                    emitLocalSessionAsInitialSession: true

                )

            )

        )

    }

}
