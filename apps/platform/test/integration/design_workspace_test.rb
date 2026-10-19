require "test_helper"
class DesignWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: {name:"Design practice",email:"design@example.test",password:"testing-password-123"}, as: :json
    assert_response :ok
    @exercise = ExerciseVersion.find_by!(slug:"webhook-delivery",version:2)
  end
  def body = response.parsed_body
  def create_design_session(mode = "guided", exercise = @exercise)
    post "/api/sessions", params:{exercise_id:exercise.id,mode:mode}, as: :json
    assert_response :created
    body
  end
  def diagram
    {"version"=>1,"nodes"=>[{"id"=>"ingest","kind"=>"service","label"=>"Ingestion API","detail"=>"Durable before acknowledgment","x"=>40,"y"=>80},{"id"=>"queue","kind"=>"queue","label"=>"Delivery queue","detail"=>"Bounded workers","x"=>350,"y"=>80}],"edges"=>[{"id"=>"flow","from"=>"ingest","to"=>"queue","label"=>"persist event"}]}
  end
  def save_session(record, files)
    put "/api/sessions/#{record['id']}/snapshot", params:{expected_revision:record['revision'],files:files}, as: :json
  end
  test "new design versions publish a full workspace while legacy attempts remain notes only" do
    get "/api/exercises"
    entry=body.fetch("exercises").find{|e|e["slug"]=="webhook-delivery"}
    assert_equal 2,entry["version"]
    assert_includes entry["tools"],"Architecture canvas"
    refute entry["executable"]
    record=create_design_session
    assert_equal DesignDocument::FILES.sort,record["editable_paths"].sort
    legacy=create_design_session("guided",ExerciseVersion.find_by!(slug:"webhook-delivery",version:1))
    assert_equal ["notes.md"],legacy["editable_paths"]
    save_session(legacy,{"notes.md"=>"# Existing writing attempt remains editable"})
    assert_response :ok
  end
  test "diagram and structured notes share one preserved revision and submission review" do
    record=create_design_session("assessment")
    files=record.fetch("files").slice(*record.fetch("editable_paths"))
    files["diagram.json"]=JSON.pretty_generate(diagram)+"\n"
    files["requirements.md"]="# Requirements\nAccepted work survives one machine failure.\n"
    save_session(record,files);assert_response :ok
    record=body
    get "/api/sessions/#{record['id']}";assert_response :ok
    assert_equal files,body.fetch("files").slice(*record.fetch("editable_paths"))
    assert_nil body["deadline_at"]
    post "/api/sessions/#{record['id']}/start",as: :json;assert_response :ok
    assert body["deadline_at"]
    post "/api/sessions/#{record['id']}/submit",params:{expected_revision:record['revision']},as: :json;assert_response :ok
    get "/api/sessions/#{record['id']}/review";assert_response :ok
    assert_equal diagram,body.fetch("design")
    assert_equal record.fetch("revision"),body.fetch("revision")
    assert_includes body.fetch("evidence_files"),"diagram.json"
    entries={"durability"=>{"rating"=>"approaching_target","notes"=>"The durable boundary is stated, but crash recovery needs work.","evidence"=>{"path"=>"requirements.md","start_line"=>2,"end_line"=>2}}}
    put "/api/sessions/#{record['id']}/review",params:{expected_version:nil,entries:entries,reflection:"Trace a worker crash next."},as: :json
    assert_response :ok
    assert_includes body.fetch("entries").fetch("durability").fetch("evidence").fetch("excerpt"),"survives one machine failure"
    save_session(record,files.merge("diagram.json"=>JSON.generate({version:1,nodes:[],edges:[]})));assert_response :conflict
  end
  test "invalid graph identities paths and omitted artifacts cannot replace a saved design" do
    record=create_design_session
    original=record.fetch("files").slice(*record.fetch("editable_paths"))
    mutations=[->(d){d["nodes"]<<d["nodes"][0].dup},->(d){d["edges"][0]["to"]="missing"},->(d){d["edges"][0]["id"]="ingest"},->(d){d["nodes"][0]["kind"]="script"},->(d){d["nodes"][0]["x"]=-1},->(d){d["edges"][0]["url"]="https://example.test"},->(d){d["version"]=true}]
    mutations.each do |mutate|
      document=diagram;mutate.call(document)
      save_session(record,original.merge("diagram.json"=>JSON.generate(document)));assert_response :unprocessable_content
    end
    save_session(record,original.except("capacity.md"));assert_response :unprocessable_content
    save_session(record,original.merge("app/evil.rb"=>"bad"));assert_response :unprocessable_content
    get "/api/sessions/#{record['id']}"
    assert_equal record.fetch("revision"),body.fetch("revision")
  end
  test "stale diagram saves preserve both original snapshots and newer work" do
    record=create_design_session
    files=record.fetch("files").slice(*record.fetch("editable_paths")).merge("diagram.json"=>JSON.generate(diagram))
    save_session(record,files);assert_response :ok
    newer=body.fetch("revision")
    save_session(record,files.merge("notes.md"=>"# Stale change"));assert_response :conflict
    get "/api/sessions/#{record['id']}"
    assert_equal newer,body.fetch("revision")
    assert_equal files["diagram.json"],body.fetch("files").fetch("diagram.json")
  end
  test "deadline submission and owner boundaries protect design artifacts" do
    record=create_design_session("assessment")
    post "/api/sessions/#{record['id']}/start",as: :json;assert_response :ok
    session=InterviewSession.find(record['id'])
    travel_to(session.deadline_at+1.second) do
      get "/api/sessions/#{record['id']}";assert_response :ok
      assert_equal "submitted",body["status"]
      assert_equal record["revision"],body["submitted_revision"]
    end
    delete "/api/logout",as: :json
    post "/api/register",params:{name:"Another",email:"other-design@example.test",password:"testing-password-123"},as: :json
    get "/api/sessions/#{record['id']}";assert_response :not_found
    get "/api/sessions/#{record['id']}/review";assert_response :not_found
  end
end
