require 'spec_helper'
require 'data_magic'
require 'hashie'

describe DataMagic::QueryBuilder do

  before :example do
    DataMagic.destroy
    ENV['DATA_PATH'] = './spec/fixtures/minimal'
    DataMagic.config = DataMagic::Config.new
  end

  after :example do
    DataMagic.destroy
  end

  RSpec.configure do |c|
    c.alias_it_should_behave_like_to :it_correctly, 'correctly:'
  end

  let(:expected_meta) { { from: 0, size: 20, _source: {:exclude=>["_*"]}} }
  let(:options) { {} }
  let(:query_hash) { DataMagic::QueryBuilder.from_params(subject, options, DataMagic.config) }

  shared_examples "builds a query" do
    it "with a query section" do
      expect(query_hash[:query]).to eql expected_query
    end
    it "with query metadata" do
      expect(query_hash.reject { |k, _| k == :query }).to eql expected_meta
    end
  end

  describe "can issue a blank query" do
    subject { {} }
    let(:expected_query) { { match_all: {} } }
    it_correctly "builds a query"
  end

  describe "can exact match on a field" do
    subject { { zipcode: "35762" } }
    let(:expected_query) { { match: { "zipcode" => { query: "35762" } } } }
    it_correctly "builds a query"
  end

  describe "can exact match on a nested field" do
    subject { { 'school.zip': "35762" } }
    let(:expected_query) { { match: { "school.zip" => { query: "35762" } } } }
    it_correctly "builds a query"
  end

  describe "can case-insensitive match on a field" do
    before do
      allow(DataMagic.config).to receive(:field_type).with(:city).and_return("name")
    end
    subject { { city: "new YORK" } }
    let(:expected_query) { { wildcard: { "_city" => { value: "new* york*" } } } }
    it_correctly "builds a query"
  end

  describe "can exact match from a list of integers" do
    before do
      allow(DataMagic.config).to receive(:field_type).with(:age).and_return("integer")
    end
    subject { { age: '10,20,40' } }
    let(:expected_query) do {
        filtered: {
            query: { match_all: {} },
            filter: {
                terms: { age: [10,20,40] }
            } } }
    end
    it_correctly "builds a query"
  end

  describe "can search within a location" do
    subject { {} }
    let(:options) { { zip: "94132", distance: "30mi" } }
    let(:expected_query) do {
      filtered: {
        query: { match_all: {} },
        filter: {
          geo_distance: {
            distance: "30mi",
            "location" => { lat: 37.7211, lon: -122.4754 }
      } } } }
    end
    it_correctly "builds a query"
  end

  describe "can handle pagination" do
    subject { {} }
    let(:options) { { page: 3, per_page: 11 } }
    let(:expected_query) { { match_all: {} } }
    let(:expected_meta)  { { from: 33, size: 11, _source: {:exclude=>["_*"]} }}
    it_correctly "builds a query"
  end

  describe "limits maximum page size" do
    subject { {} }
    let(:options) { { page: 0, per_page: 2000 } }
    let(:expected_query) { { match_all: {} } }
    let(:expected_meta)  { { from: 0, size: 100, _source: {:exclude=>["_*"]} }}
    it_correctly "builds a query"
  end

  describe "can specify fields to return" do
    subject { {} }
    let(:options) { { fields: ["id" ,"school.name"] } }
    let(:expected_query) { { match_all: {} } }
    let(:expected_meta)  do
      { from: 0, size: 20, _source: false,
        fields: ["id" ,"school.name"]
      }
    end
    it_correctly "builds a query"
  end

  describe "can specify sort order" do
    subject { {} }
    let(:options) { { sort: "population:asc" } }
    let(:expected_query) { { match_all: {} } }
    let(:expected_meta)  do
      { from: 0, size: 20,
        _source: {:exclude=>["_*"]},
        sort: [{ "population" => { order: "asc" } }]
      }
    end
    it_correctly "builds a query"
  end

  describe "can sort by multiple fields" do
    subject { {} }
    let(:options) { { sort: "state:desc, population:asc,name" } }
    let(:expected_query) { { match_all: {} } }
    let(:expected_meta)  do
      { from: 0, size: 20,
        _source: {:exclude=>["_*"]},
        sort: [{ 'state' => { order: 'desc' } },
               { "population" => { order: "asc" } },
               { 'name' => { order: 'asc' } }]
      }
    end
    it_correctly "builds a query"
  end

  describe "can search using the __range operator" do
    context "that is open-ended (left-hand side)" do
      subject { { age__range: '10..' } }
      let(:expected_query) do {
        filtered: {
          query: { match_all: {} },
          filter: {
            or: [{ range: { age: { gte: 10 } } }]
          } } }
      end
      it_correctly "builds a query"
    end

    context "that is open-ended (right-hand side)" do
      subject { { age__range: '..10' } }
      let(:expected_query) do {
        filtered: {
          query: { match_all: {} },
          filter: {
            or: [{ range: { age: { lte: 10 } } }]
          } } }
      end
      it_correctly "builds a query"
    end

    context "that is closed" do
      subject { { age__range: '10..20' } }
      let(:expected_query) do {
        filtered: {
          query: { match_all: {} },
          filter: {
            or: [{ range: { age: { gte: 10, lte: 20 } } }]
        } } }
      end
      it_correctly "builds a query"
    end

    context "that has multiple ranges" do
      subject { { age__range: '10..20,30..40' } }
      let(:expected_query) do {
        filtered: {
          query: { match_all: {} },
          filter: {
            or: [
              { range: { age: { gte: 10, lte: 20 } } },
              { range: { age: { gte: 30, lte: 40 } } }
            ]
          } } }
      end
      it_correctly "builds a query"
    end
  end

  describe 'converts values to the correct type' do
    subject { { population__range: '1000..' } }
    let(:expected_query) do {
      filtered: {
        query: { match_all: {} },
        filter: { or: [ { range: { population: { gte: 1000 } } } ] }
      }
    }
    end
    it_correctly "builds a query"
  end

  describe 'negates values' do
    let(:expected_query) do {
      bool: { must_not: [ { match: { 'state' => { query: 'CA' } } } ] }
    }
    end
    context 'with "__ne"' do
      subject { { state__ne: 'CA' } }
      it_correctly "builds a query"
    end
    context 'with "__not"' do
      subject { { state__not: 'CA' } }
      it_correctly "builds a query"
    end
  end

  describe 'allows matching and negation of the different fields' do
    subject { { name: 'San Francisco', state__ne: 'CA' } }
    let(:expected_query) do {
      bool: {
        must: [ { match: { 'name' => { query: 'San Francisco' } } } ],
        must_not: [ { match: { 'state' => { query: 'CA' } } } ]
      }
    }
    end
    it_correctly "builds a query"
  end
end
