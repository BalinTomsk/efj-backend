** How write unit tests

-- unit test must use real tables - no stubs,  for some results unit test can use table as  avalue. you cam use local service and ffi database for testing.   

-- unit test should not change state of database when finished

-- normal output for successed unmit test only one line like: TEST 5 PASS: fn_fish_image_handler returned correct image binary

