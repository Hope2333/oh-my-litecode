export interface WeatherConfig {
  enabled: boolean;
}

export interface WeatherResult {
  success: boolean;
  output?: string;
  error?: string;
}
