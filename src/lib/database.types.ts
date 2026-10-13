export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
	public: {
		Tables: {
			profiles: {
				Row: {
					id: string;
					full_name: string | null;
					phone_number: string | null;
					created_at: string;
				};
				Insert: {
					id: string;
					full_name?: string | null;
					phone_number?: string | null;
					created_at?: string;
				};
				Update: {
					full_name?: string | null;
					phone_number?: string | null;
				};
				Relationships: [];
			};
			incidents: {
				Row: {
					id: string;
					user_id: string;
					title: string;
					description: string | null;
					category: Database['public']['Enums']['incident_category'];
					severity: Database['public']['Enums']['incident_severity'];
					address_hint: string | null;
					media_urls: string[];
					status: Database['public']['Enums']['incident_status'];
					is_sos: boolean;
					created_at: string;
					updated_at: string;
				};
				Insert: {
					id?: string;
					user_id: string;
					title: string;
					description?: string | null;
					category: Database['public']['Enums']['incident_category'];
					severity: Database['public']['Enums']['incident_severity'];
					address_hint?: string | null;
					media_urls?: string[];
					status?: Database['public']['Enums']['incident_status'];
					is_sos?: boolean;
					created_at?: string;
					updated_at?: string;
				};
				Update: {
					title?: string;
					description?: string | null;
					category?: Database['public']['Enums']['incident_category'];
					severity?: Database['public']['Enums']['incident_severity'];
					address_hint?: string | null;
					media_urls?: string[];
					status?: Database['public']['Enums']['incident_status'];
				};
				Relationships: [];
			};
			incident_comments: {
				Row: {
					id: string;
					incident_id: string;
					user_id: string;
					comment: string;
					media_url: string | null;
					created_at: string;
				};
				Insert: {
					id?: string;
					incident_id: string;
					user_id: string;
					comment: string;
					media_url?: string | null;
					created_at?: string;
				};
				Update: {
					comment?: string;
					media_url?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'incident_comments_user_id_fkey';
						columns: ['user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['id'];
					}
				];
			};
			incident_confirmations: {
				Row: {
					id: string;
					incident_id: string;
					user_id: string;
					vote_type: Database['public']['Enums']['vote_type'];
					created_at: string;
				};
				Insert: {
					id?: string;
					incident_id: string;
					user_id: string;
					vote_type: Database['public']['Enums']['vote_type'];
					created_at?: string;
				};
				Update: {
					vote_type?: Database['public']['Enums']['vote_type'];
				};
				Relationships: [];
			};
			action_logs: {
				Row: {
					id: string;
					user_id: string | null;
					action_type: string;
					entity_type: string;
					entity_id: string | null;
					metadata: Json;
					created_at: string;
				};
				Insert: {
					id?: string;
					user_id: string;
					action_type: string;
					entity_type: string;
					entity_id?: string | null;
					metadata?: Json;
					created_at?: string;
				};
				Update: never;
				Relationships: [];
			};
		};
		Views: {
			[_ in never]: never;
		};
		Functions: {
			create_incident: {
				Args: {
					p_title: string;
					p_description: string | null;
					p_category: string;
					p_severity: string;
					p_lng: number;
					p_lat: number;
					p_address_hint?: string | null;
					p_media_urls?: string[];
					p_is_sos?: boolean;
				};
				Returns: string;
			};
			get_incidents: {
				Args: {
					hours_back?: number;
					category_filter?: string | null;
					min_lng?: number | null;
					min_lat?: number | null;
					max_lng?: number | null;
					max_lat?: number | null;
				};
				Returns: {
					id: string;
					user_id: string;
					title: string;
					description: string | null;
					category: string;
					severity: string;
					lng: number;
					lat: number;
					address_hint: string | null;
					media_urls: string[] | null;
					status: string;
					is_sos: boolean;
					created_at: string;
					updated_at: string;
					confirm_count: number;
					deny_count: number;
					comment_count: number;
					author_name: string | null;
				}[];
			};
			get_5km_grid: {
				Args: {
					hours_back?: number;
					category_filter?: string | null;
				};
				Returns: Json;
			};
		};
		Enums: {
			incident_category: 'fire' | 'looting' | 'casualty' | 'accident' | 'roadblock' | 'sos' | 'other';
			incident_severity: 'low' | 'medium' | 'high' | 'critical';
			incident_status: 'unverified' | 'verified' | 'resolved' | 'debunked';
			vote_type: 'confirm' | 'deny';
		};
		CompositeTypes: {
			[_ in never]: never;
		};
	};
};
