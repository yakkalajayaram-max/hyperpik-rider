/// Where the rider app talks to. The anon key is public by design; every rider call goes through the website, which
/// checks who is asking.
class AppConfig {
  static const supabaseUrl = 'https://qaolnxcmmomyhftheknr.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhb2xueGNtbW9teWhmdGhla25yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2MjExNzcsImV4cCI6MjEwMjE5NzE3N30.BHBXDNS3HwLkYYlO0uu_eJZ6iwprd6AXC9dFRn8AzVA';
  static const siteUrl = 'https://hyperpik.com';
  static const phoneCountryCode = '+91';
}
