

class DataMagic
  class InvalidData < StandardError
  end

  require 'elasticsearch'
  require 'yaml'
  @@client = Elasticsearch::Client.new #log: true
  @@files = []
  @@mapping = {}
  @@api_endpoints = {}

  class << self
    require 'csv'

    def client
      @@client
    end

    def files
      @@files
    end

    def mapping
      @@mapping
    end

    def find_index_for(api)
      @@api_endpoints[api][:index]
    end

    def scoped_index_name(index_name)
      env = ENV['RACK_ENV']
      "#{env}-#{index_name}"
    end

    def delete_all
      client.indices.delete index: '_all'
      client.indices.clear_cache
      @@files = []
    end

    def delete_index(index_name)
      index_name = scoped_index_name(index_name)
      client.indices.delete index: index_name
      client.indices.clear_cache
      # TODO: remove some entries from @@files
    end

    def import_csv(index_name, datafile, options={})
      unless datafile.respond_to?(:read)
        raise ArgumentError, "can't read datafile #{datafile.inspect}"
      end
      index_name = scoped_index_name(index_name)
      data = datafile.read

      if options[:force_utf8]
        data = data.encode('UTF-8', invalid: :replace, replace: '')
      end

      fields = nil
      new_fields = options[:fields]
      num_rows = 0
      begin
        CSV.parse(data, headers:true, :header_converters=> lambda {|f| f.strip.to_sym }) do |row|
          fields ||= row.headers
          row = row.to_hash
          if new_fields
            mapped = {}
            row.each do |key, value|
              new_key = new_fields[key.to_sym] || new_fields[key.to_s]
              mapped[new_key] = value if new_key
            end
            row = mapped
          end
          client.index index:index_name, type:'document', body: row
          num_rows += 1
        end
      rescue Exception => e
        puts "row #{num_rows}: #{e.message}"
      end

      raise InvalidData, "invalid file format or zero rows" if num_rows == 0

      fields = new_fields.values if new_fields
      client.indices.refresh index: index_name if num_rows > 0

      return [num_rows, fields ]
    end

    def import_all(directory_path, options = {})
      files = Dir.glob("#{directory_path}/**/*.csv").select { |entry| File.file? entry }
      config = YAML.load_file("#{directory_path}/data.yaml")
      index = config['index'] || 'general'
      mapping[index] = config['files']

      files.each do |filepath|
        fname = filepath.split('/').last
        file_config = mapping[index][fname] || []
        options[:fields] = file_config['fields'] #if mapping[index][fname] && mapping[index][fname]['fields']
        endpoint = file_config['api'] || 'data'
        @@api_endpoints[endpoint] = {index: index}
        begin
          puts "reading #{filepath}"
          File.open(filepath) do |file|
            rows, fields = DataMagic.import_csv(index, file, options)
            puts "imported #{rows} rows"
          end
          @@files << filepath
        rescue Exception => e
          puts "Error: skipping #{filepath}, #{e.message}"
        end
      end
    end

    # get the real index name when given either
    # api: api endpoint configured in data.yaml
    # index: index name
    def index_name_from_options(options)
      options[:api] = options['api'].to_sym if options['api']
      options[:index] = options['index'].to_sym if options['index']
      puts "WARNING: DataMagic.search options api will override index, only one expected"  if options[:api] and options[:index]
      if options[:api]
        index_name = find_index_for(options[:api])
        if index_name.nil?
          raise ArgumentError, "no configuration found for #{options[:api]}"
        end
      else
        index_name = options[:index]
      end
      index_name = scoped_index_name(index_name)
    end

    # thin layer on elasticsearch query
    def search(query, options = {})
      index_name = index_name_from_options(options)
      full_query = {index: index_name, body: query}
      result = client.search full_query
      hits = result["hits"]
      hits["hits"].map {|hit| hit["_source"]}
    end
  end
end